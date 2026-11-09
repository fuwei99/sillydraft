import 'package:path/path.dart' as p;

import 'errors.dart';
import 'paths.dart';

enum MountMode {
  ro,
  rw;

  static MountMode parse(String value) => switch (value) {
    'rw' => MountMode.rw,
    'ro' => MountMode.ro,
    _ => throw FormatException('未知挂载模式：$value'),
  };
}

/// One row of the mount table: a host directory made visible at a guest path.
///
/// The table is the *only* source of visibility. Nothing on the host is
/// reachable unless a row points at it.
final class MountEntry {
  MountEntry({
    required String hostPath,
    required String guestPath,
    this.mode = MountMode.ro,
    String? label,
    this.builtIn = false,
  }) : hostPath = _cleanHost(hostPath),
       guestPath = normalizeGuestPath(guestPath),
       label = label ?? p.basename(normalizeGuestPath(guestPath)) {
    if (!p.isAbsolute(this.hostPath)) {
      throw FormatException('挂载源必须是绝对路径：${this.hostPath}');
    }
  }

  final String hostPath;
  final String guestPath;
  final MountMode mode;

  /// Short name used by the prompt and the UI, e.g. `sillydraft`.
  final String label;

  /// Built-in rows cannot be deleted by the user.
  final bool builtIn;

  bool get writable => mode == MountMode.rw;

  Map<String, dynamic> toJson() => {
    'host': hostPath,
    'guest': guestPath,
    'mode': mode.name,
    'label': label,
    if (builtIn) 'builtIn': true,
  };

  factory MountEntry.fromJson(Map<String, dynamic> json) => MountEntry(
    hostPath: json['host'] as String,
    guestPath: json['guest'] as String,
    mode: MountMode.parse(json['mode'] as String? ?? 'ro'),
    label: json['label'] as String?,
    builtIn: json['builtIn'] == true,
  );

  static String _cleanHost(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) throw const FormatException('挂载源不能为空');
    return p.normalize(trimmed);
  }
}

/// A guest path resolved back to the host file it names.
final class ResolvedPath {
  const ResolvedPath({
    required this.entry,
    required this.guestPath,
    required this.hostPath,
    required this.relativePath,
  });

  final MountEntry entry;
  final String guestPath;
  final String hostPath;

  /// Path relative to the mount root, `''` for the mount root itself.
  final String relativePath;

  bool get writable => entry.writable;
}

/// The mount table. Rows are sorted longest-guest-first so resolution is a
/// plain prefix walk.
final class MountTable {
  MountTable._(this.entries);

  factory MountTable(List<MountEntry> entries) {
    final sorted = [...entries]
      ..sort((a, b) => b.guestPath.length.compareTo(a.guestPath.length));
    final table = MountTable._(List.unmodifiable(sorted));
    table._validate();
    return table;
  }

  /// The table a fresh install has: the agent's scratch area plus exactly one
  /// user-visible mount, the library.
  factory MountTable.standard({
    required String workspaceHost,
    required String dataHost,
    MountMode dataMode = MountMode.rw,
  }) => MountTable([
    MountEntry(
      hostPath: workspaceHost,
      guestPath: WorkspacePaths.workspace,
      mode: MountMode.rw,
      label: 'workspace',
      builtIn: true,
    ),
    MountEntry(
      hostPath: dataHost,
      guestPath: WorkspacePaths.data,
      mode: dataMode,
      label: WorkspacePaths.dataLabel,
      builtIn: true,
    ),
  ]);

  factory MountTable.fromJson({
    required String workspaceHost,
    required Map<String, dynamic> json,
  }) {
    final rows = json['mounts'] as List<dynamic>? ?? const <dynamic>[];
    return MountTable([
      MountEntry(
        hostPath: workspaceHost,
        guestPath: WorkspacePaths.workspace,
        mode: MountMode.rw,
        label: 'workspace',
        builtIn: true,
      ),
      for (final row in rows)
        if (row is Map<String, dynamic>) MountEntry.fromJson(row),
    ]);
  }

  final List<MountEntry> entries;

  /// Hosts that would expose the whole device or a system area. A mount of
  /// `/storage/emulated/0/Documents/x` is fine; `/storage` is not.
  static const List<String> forbiddenHosts = [
    '/',
    '/sdcard',
    '/storage',
    '/storage/emulated',
    '/storage/emulated/0',
    '/data',
    '/system',
    '/proc',
    '/sys',
    '/dev',
  ];

  void _validate() {
    final guests = <String>{};
    var hasWorkspace = false;
    for (final entry in entries) {
      if (entry.guestPath == WorkspacePaths.workspace) {
        hasWorkspace = true;
      } else if (!entry.guestPath.startsWith('${WorkspacePaths.mountRoot}/')) {
        throw FormatException(
          '挂载点必须位于 ${WorkspacePaths.mountRoot}/ 下：${entry.guestPath}',
        );
      }
      if (!guests.add(entry.guestPath)) {
        throw FormatException('挂载点重复：${entry.guestPath}');
      }
      for (final forbidden in forbiddenHosts) {
        if (entry.hostPath == forbidden ||
            isWithinOrEqual(entry.hostPath, forbidden)) {
          throw FormatException(
            '不允许挂载 $forbidden（会暴露整个设备或系统目录）：${entry.hostPath}',
          );
        }
      }
    }
    if (!hasWorkspace) {
      throw StateError('挂载表必须包含 ${WorkspacePaths.workspace}');
    }
  }

  /// Resolve a guest path to its host file. Throws [OutsideWorkspaceException]
  /// when no row covers it.
  ResolvedPath resolve(String guestPath) {
    final normalized = normalizeGuestPath(guestPath);
    for (final entry in entries) {
      if (normalized == entry.guestPath) {
        return ResolvedPath(
          entry: entry,
          guestPath: normalized,
          hostPath: entry.hostPath,
          relativePath: '',
        );
      }
      final prefix = '${entry.guestPath}/';
      if (normalized.startsWith(prefix)) {
        final relative = normalized.substring(prefix.length);
        return ResolvedPath(
          entry: entry,
          guestPath: normalized,
          hostPath: p.joinAll([entry.hostPath, ...relative.split('/')]),
          relativePath: relative,
        );
      }
    }
    throw OutsideWorkspaceException(guestPath);
  }

  /// Resolve and refuse read-only mounts.
  ResolvedPath resolveForWrite(String guestPath) {
    final resolved = resolve(guestPath);
    if (!resolved.writable) {
      throw ReadOnlyMountException(guestPath, resolved.entry.guestPath);
    }
    return resolved;
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'mounts': [
      for (final entry in entries)
        if (!entry.builtIn || entry.guestPath != WorkspacePaths.workspace)
          entry.toJson(),
    ],
  };
}

/// Normalize a guest path: absolute, no `.`/`..`, no duplicate slashes.
String normalizeGuestPath(String input) {
  if (!input.startsWith('/')) {
    throw FormatException('路径必须是绝对路径：$input');
  }
  final parts = <String>[];
  for (final segment in input.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (parts.isEmpty) {
        throw FormatException('路径越界：$input');
      }
      parts.removeLast();
      continue;
    }
    parts.add(segment);
  }
  return '/${parts.join('/')}';
}

/// True when [path] equals [root] or sits below it, comparing whole segments.
bool isWithinOrEqual(String root, String path) {
  final r = _trimTrailingSlash(root);
  final t = _trimTrailingSlash(path);
  return t == r || t.startsWith('$r/');
}

String _trimTrailingSlash(String value) {
  if (value == '/') return value;
  var end = value.length;
  while (end > 1 && value.codeUnitAt(end - 1) == 0x2F) {
    end--;
  }
  return value.substring(0, end);
}
