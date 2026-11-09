import 'dart:convert';
import 'dart:io';

import 'package:sillydraft_workspace/sillydraft_workspace.dart';

/// Tiny driver for the desktop: prints the prompt, runs a command, or reads a
/// file through the same mount table the Android build uses.
Future<void> main(List<String> argv) async {
  try {
    await _run(argv);
  } on WorkspaceException catch (e) {
    stderr.writeln(e.message);
    exit(1);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exit(64);
  }
}

Future<void> _run(List<String> argv) async {
  final args = _Args.parse(argv);
  final table = MountTable([
    MountEntry(
      hostPath: args.workspace,
      guestPath: WorkspacePaths.workspace,
      mode: MountMode.rw,
      label: 'workspace',
      builtIn: true,
    ),
    MountEntry(
      hostPath: args.data,
      guestPath: WorkspacePaths.data,
      mode: MountMode.rw,
      label: WorkspacePaths.dataLabel,
      builtIn: true,
    ),
    for (final mount in args.mounts)
      MountEntry(
        hostPath: mount.host,
        guestPath: '/mnt/${mount.label}',
        mode: mount.mode,
        label: mount.label,
      ),
  ]);

  if (args.prompt) {
    stdout.write(buildWorkspacePrompt(table));
    return;
  }

  if (args.command != null) {
    final result = await HostShellRunner(table)
        .run(ShellRequest(command: args.command!, cwd: args.cwd));
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
    return;
  }

  if (args.read != null) {
    final result = await WorkspaceFiles(table).read(args.read!);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
    return;
  }

  stderr.writeln(
    '用法：ws --workspace <host> --data <host> [--mount label=host[:ro]] '
    '[--prompt | --run "<cmd>" | --read <guest-path>]',
  );
  exit(64);
}

final class _Args {
  _Args({
    required this.workspace,
    required this.data,
    required this.mounts,
    required this.prompt,
    required this.command,
    required this.read,
    required this.cwd,
  });

  final String workspace;
  final String data;
  final List<_MountArg> mounts;
  final bool prompt;
  final String? command;
  final String? read;
  final String cwd;

  static _Args parse(List<String> argv) {
    String? workspace;
    String? data;
    final mounts = <_MountArg>[];
    var prompt = false;
    String? command;
    String? read;
    var cwd = WorkspacePaths.workspace;

    for (var i = 0; i < argv.length; i++) {
      final arg = argv[i];
      String next() {
        if (i + 1 >= argv.length) {
          throw FormatException('$arg 缺少参数');
        }
        return argv[++i];
      }

      switch (arg) {
        case '--workspace':
          workspace = next();
        case '--data':
          data = next();
        case '--mount':
          mounts.add(_MountArg.parse(next()));
        case '--prompt':
          prompt = true;
        case '--run':
          command = next();
        case '--read':
          read = next();
        case '--cwd':
          cwd = next();
        default:
          throw FormatException('未知参数：$arg');
      }
    }

    if (workspace == null || data == null) {
      throw const FormatException('--workspace 和 --data 必填');
    }
    return _Args(
      workspace: workspace,
      data: data,
      mounts: mounts,
      prompt: prompt,
      command: command,
      read: read,
      cwd: cwd,
    );
  }
}

final class _MountArg {
  const _MountArg(this.label, this.host, this.mode);

  final String label;
  final String host;
  final MountMode mode;

  static _MountArg parse(String value) {
    final equals = value.indexOf('=');
    if (equals <= 0) {
      throw FormatException('--mount 需要 label=host[:ro|rw]：$value');
    }
    final label = value.substring(0, equals);
    var host = value.substring(equals + 1);
    var mode = MountMode.ro;
    if (host.endsWith(':rw')) {
      host = host.substring(0, host.length - 3);
      mode = MountMode.rw;
    } else if (host.endsWith(':ro')) {
      host = host.substring(0, host.length - 3);
    }
    return _MountArg(label, host, mode);
  }
}
