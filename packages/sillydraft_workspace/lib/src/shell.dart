import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'mounts.dart';
import 'paths.dart';
import 'proot.dart';

final class ShellRequest {
  const ShellRequest({
    required this.command,
    this.cwd = WorkspacePaths.workspace,
    this.timeout = const Duration(seconds: 30),
    this.background = false,
  });

  final String command;

  /// Guest path, or a path relative to `/workspace`.
  final String cwd;
  final Duration timeout;
  final bool background;
}

final class ShellResult {
  const ShellResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
    required this.truncated,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final bool truncated;

  bool get ok => exitCode == 0 && !timedOut;

  Map<String, dynamic> toJson() => {
    'exitCode': exitCode,
    'stdout': stdout,
    'stderr': stderr,
    'timedOut': timedOut,
    if (truncated) 'truncated': true,
  };
}

abstract interface class ShellRunner {
  Future<ShellResult> run(ShellRequest request);
}

/// Runs commands with the host `/bin/sh` and the mount table mapped to real
/// directories. Used by tests and by the desktop build; Android uses
/// [ProotCommandBuilder] instead.
final class HostShellRunner implements ShellRunner {
  HostShellRunner(this.table, {this.maxOutputBytes = 256 * 1024});

  final MountTable table;
  final int maxOutputBytes;

  @override
  Future<ShellResult> run(ShellRequest request) async {
    if (request.background) {
      throw UnsupportedError('后台命令需要 Android 端的前台服务');
    }
    final cwdGuest = request.cwd.startsWith('/')
        ? normalizeGuestPath(request.cwd)
        : normalizeGuestPath('${WorkspacePaths.workspace}/${request.cwd}');
    final resolved = table.resolve(cwdGuest);

    // A new session lets a timeout kill the whole tree, not just the shell.
    final setsid = _findSetsid();
    final process = await Process.start(
      setsid ?? '/bin/sh',
      setsid == null
          ? ['-c', request.command]
          : ['/bin/sh', '-c', request.command],
      workingDirectory: resolved.hostPath,
    );
    return _collect(
      process,
      request.timeout,
      maxOutputBytes,
      killGroup: setsid != null,
    );
  }

  static String? _findSetsid() {
    for (final path in ['/usr/bin/setsid', '/bin/setsid']) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }
}

/// Runs commands inside the PRoot rootfs on Android.
final class ProotShellRunner implements ShellRunner {
  ProotShellRunner({
    required this.builder,
    required this.table,
    this.maxOutputBytes = 256 * 1024,
  });

  final ProotCommandBuilder builder;
  final MountTable table;
  final int maxOutputBytes;

  @override
  Future<ShellResult> run(ShellRequest request) async {
    if (request.background) {
      throw UnsupportedError('后台命令需要 Android 端的前台服务');
    }
    final command = builder.build(
      table: table,
      command: request.command,
      cwd: request.cwd,
    );
    final process = await Process.start(
      command.executable,
      command.args,
      environment: command.environment,
      workingDirectory: command.workingDirectory,
    );
    // PRoot's --kill-on-exit takes the guest tree down with this process.
    return _collect(process, request.timeout, maxOutputBytes);
  }
}

Future<ShellResult> _collect(
  Process process,
  Duration timeout,
  int maxOutputBytes, {
  bool killGroup = false,
}) async {
  final out = _Collector(maxOutputBytes);
  final err = _Collector(maxOutputBytes);
  final outDone = process.stdout.forEach(out.add);
  final errDone = process.stderr.forEach(err.add);

  var timedOut = false;
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      timedOut = true;
      if (killGroup) {
        Process.killPid(-process.pid, ProcessSignal.sigkill);
      } else {
        process.kill(ProcessSignal.sigkill);
      }
      return -1;
    },
  );
  // A grandchild may still hold the pipes; do not wait on it forever.
  await Future.wait([outDone, errDone])
      .timeout(const Duration(seconds: 2), onTimeout: () => const <void>[]);

  return ShellResult(
    exitCode: exitCode,
    stdout: out.text,
    stderr: err.text,
    timedOut: timedOut,
    truncated: out.truncated || err.truncated,
  );
}

/// Keeps the first and last part of a stream, so both the beginning of a
/// listing and the tail of a stack trace survive truncation.
final class _Collector {
  _Collector(this.limit);

  final int limit;
  final BytesBuilder _head = BytesBuilder();
  final BytesBuilder _tail = BytesBuilder();
  int _seen = 0;

  bool get truncated => _seen > limit;

  void add(List<int> chunk) {
    _seen += chunk.length;
    final headRoom = limit ~/ 2 - _head.length;
    if (headRoom > 0) {
      _head.add(chunk.take(headRoom).toList());
    }
    _tail.add(chunk);
    if (_tail.length > limit ~/ 2) {
      final all = _tail.takeBytes();
      _tail.add(all.sublist(all.length - limit ~/ 2));
    }
  }

  String get text {
    if (!truncated) return utf8.decode(_head.takeBytes(), allowMalformed: true);
    final head = utf8.decode(_head.takeBytes(), allowMalformed: true);
    final tail = utf8.decode(_tail.takeBytes(), allowMalformed: true);
    return '$head\n…[truncated ${_seen - limit} bytes]…\n$tail';
  }
}
