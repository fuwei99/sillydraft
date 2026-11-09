import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'errors.dart';
import 'mounts.dart';

/// The result of reading a guest file. Exactly one of [text] and [bytes] is
/// set; images come back as bytes for the multimodal channel.
final class ReadOutcome {
  const ReadOutcome({
    required this.guestPath,
    required this.hostPath,
    required this.byteLength,
    this.text,
    this.bytes,
    this.mimeType,
  });

  final String guestPath;
  final String hostPath;
  final int byteLength;
  final String? text;
  final Uint8List? bytes;
  final String? mimeType;

  bool get isImage => mimeType != null;

  Map<String, dynamic> toJson() => {
    'path': guestPath,
    'bytes': byteLength,
    if (text != null) 'text': text,
    if (mimeType != null)
      'image': {'mimeType': mimeType, 'base64': base64Encode(bytes!)},
  };
}

final class WriteOutcome {
  const WriteOutcome({
    required this.guestPath,
    required this.hostPath,
    required this.hash,
    required this.byteLength,
  });

  final String guestPath;
  final String hostPath;
  final String hash;
  final int byteLength;

  Map<String, dynamic> toJson() => {
    'path': guestPath,
    'hash': hash,
    'bytes': byteLength,
  };
}

/// File operations over a [MountTable]. Every path goes through
/// [MountTable.resolve]; every write is atomic; every access re-checks that
/// symlinks did not walk out of the mount.
final class WorkspaceFiles {
  WorkspaceFiles(this.table);

  final MountTable table;
  final Map<String, String> _realRoots = {};

  static const int defaultMaxReadBytes = 8 * 1024 * 1024;

  Future<String> _realRoot(MountEntry entry) async {
    final cached = _realRoots[entry.guestPath];
    if (cached != null) return cached;
    final dir = Directory(entry.hostPath);
    final real = await dir.exists()
        ? await dir.resolveSymbolicLinks()
        : p.normalize(entry.hostPath);
    _realRoots[entry.guestPath] = real;
    return real;
  }

  /// Reject a path that resolves outside its mount through a symlink.
  Future<void> _guard(ResolvedPath resolved) async {
    final root = await _realRoot(resolved.entry);
    final file = File(resolved.hostPath);
    String target;
    if (await file.exists()) {
      target = await file.resolveSymbolicLinks();
    } else {
      var parent = file.parent;
      while (!await parent.exists()) {
        final up = parent.parent;
        if (up.path == parent.path) break;
        parent = up;
      }
      final realParent = await parent.resolveSymbolicLinks();
      final tail = p.relative(resolved.hostPath, from: parent.path);
      target = p.normalize(p.join(realParent, tail));
    }
    if (!isWithinOrEqual(root, target)) {
      throw OutsideWorkspaceException(resolved.guestPath);
    }
  }

  Future<ReadOutcome> read(
    String guestPath, {
    int maxBytes = defaultMaxReadBytes,
  }) async {
    final resolved = table.resolve(guestPath);
    await _guard(resolved);
    final file = File(resolved.hostPath);
    if (!await file.exists()) throw GuestFileNotFound(guestPath);
    final length = await file.length();
    if (length > maxBytes) {
      throw GuestFileTooLarge(guestPath, length, maxBytes);
    }
    final bytes = await file.readAsBytes();
    final mime = _imageMimeType(resolved.hostPath);
    if (mime != null) {
      return ReadOutcome(
        guestPath: resolved.guestPath,
        hostPath: resolved.hostPath,
        byteLength: bytes.length,
        bytes: bytes,
        mimeType: mime,
      );
    }
    try {
      return ReadOutcome(
        guestPath: resolved.guestPath,
        hostPath: resolved.hostPath,
        byteLength: bytes.length,
        text: utf8.decode(bytes),
      );
    } on FormatException {
      throw NotTextFile(guestPath);
    }
  }

  /// Write a whole file. Pass [baseHash] (from a previous [read] or
  /// [WriteOutcome]) to refuse the write when the file changed meanwhile.
  Future<WriteOutcome> write(
    String guestPath,
    String text, {
    String? baseHash,
  }) async {
    final resolved = table.resolveForWrite(guestPath);
    await _guard(resolved);
    final file = File(resolved.hostPath);
    final bytes = utf8.encode(text);
    final hash = sha256.convert(bytes).toString();

    if (baseHash != null) {
      final current = await file.exists()
          ? sha256.convert(await file.readAsBytes()).toString()
          : null;
      if (current != baseHash) {
        throw ContentConflict(
          path: guestPath,
          expected: baseHash,
          actual: current,
        );
      }
    }

    await file.parent.create(recursive: true);
    final temp = File(
      p.join(file.parent.path, '.${p.basename(file.path)}.${_nonce()}.tmp'),
    );
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
    return WriteOutcome(
      guestPath: resolved.guestPath,
      hostPath: resolved.hostPath,
      hash: hash,
      byteLength: bytes.length,
    );
  }

  /// Replace exactly one occurrence of [oldString]. Ambiguity is an error,
  /// never a guess.
  Future<WriteOutcome> edit(
    String guestPath, {
    required String oldString,
    required String newString,
  }) async {
    if (oldString.isEmpty) {
      throw const FormatException('old_string 不能为空');
    }
    final current = await read(guestPath);
    final text = current.text;
    if (text == null) throw NotTextFile(guestPath);

    final first = text.indexOf(oldString);
    if (first < 0) throw EditTargetNotFound(guestPath);
    final second = text.indexOf(oldString, first + oldString.length);
    if (second >= 0) {
      final count = _countOccurrences(text, oldString);
      throw AmbiguousEdit(guestPath, count);
    }
    final updated =
        text.substring(0, first) +
        newString +
        text.substring(first + oldString.length);
    return write(
      guestPath,
      updated,
      baseHash: sha256.convert(utf8.encode(text)).toString(),
    );
  }

  static int _countOccurrences(String haystack, String needle) {
    var count = 0;
    var index = 0;
    while (true) {
      final found = haystack.indexOf(needle, index);
      if (found < 0) return count;
      count++;
      index = found + needle.length;
    }
  }

  static String _nonce() {
    final random = Random.secure();
    return List.generate(
      8,
      (_) => random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static const Map<String, String> _imageMimes = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'bmp': 'image/bmp',
    'svg': 'image/svg+xml',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'avif': 'image/avif',
    'ico': 'image/x-icon',
  };

  static String? _imageMimeType(String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    return _imageMimes[ext];
  }
}
