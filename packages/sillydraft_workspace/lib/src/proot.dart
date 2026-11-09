import 'dart:io';

import 'mounts.dart';
import 'paths.dart';

/// A ready-to-spawn PRoot invocation.
final class ProotCommand {
  const ProotCommand({
    required this.executable,
    required this.args,
    required this.environment,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> args;
  final Map<String, String> environment;

  /// Host directory to start the process in; the guest cwd comes from `-w`.
  final String workingDirectory;
}

/// Builds the PRoot command line for Android.
///
/// The rootfs is the whole guest filesystem. The only host directories that
/// appear inside it are the rows of [MountTable] plus the kernel filesystems
/// PRoot needs. Nothing else is reachable by path.
final class ProotCommandBuilder {
  ProotCommandBuilder({
    required this.rootfsDir,
    required this.prootExecutable,
    required this.loaderPath,
    required this.tempDir,
    required this.hostWorkingDirectory,
    this.shell = '/bin/sh',
    this.home = '/root',
  });

  final String rootfsDir;

  /// `libproot_exec.so` inside the APK's native library directory.
  final String prootExecutable;

  /// `libproot_loader.so`: PRoot loads guest binaries through it, so the
  /// kernel never has to `execve` a file in app-private storage.
  final String loaderPath;

  final String tempDir;
  final String hostWorkingDirectory;
  final String shell;
  final String home;

  static const List<String> kernelMounts = ['/dev', '/proc', '/sys'];

  ProotCommand build({
    required MountTable table,
    required String command,
    String cwd = WorkspacePaths.workspace,
  }) {
    final guestCwd = cwd.startsWith('/')
        ? normalizeGuestPath(cwd)
        : normalizeGuestPath('${WorkspacePaths.workspace}/$cwd');

    final args = <String>[
      '--root-id',
      '--link2symlink',
      '--kill-on-exit',
      '-r',
      rootfsDir,
      '-w',
      guestCwd,
      for (final entry in table.entries) ...[
        '-b',
        '${entry.hostPath}:${entry.guestPath}',
      ],
      for (final path in kernelMounts)
        if (Directory(path).existsSync()) ...['-b', path],
      '/usr/bin/env',
      '-i',
      'HOME=$home',
      'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      'TERM=dumb',
      'CI=true',
      'NO_COLOR=1',
      'PAGER=cat',
      shell,
      '-l',
      '-c',
      // The command arrives as a positional argument, so no shell escaping is
      // applied to it anywhere between Dart and the guest.
      'cd -- "\$1" && eval "\$2"',
      'sillydraft',
      guestCwd,
      command,
    ];

    return ProotCommand(
      executable: prootExecutable,
      args: args,
      environment: {
        'PROOT_LOADER': loaderPath,
        'PROOT_TMP_DIR': tempDir,
        'TMPDIR': tempDir,
      },
      workingDirectory: hostWorkingDirectory,
    );
  }
}
