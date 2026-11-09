import 'dart:convert';

import 'errors.dart';
import 'files.dart';
import 'shell.dart';

final class ToolCallResult {
  const ToolCallResult(this.content, {this.isError = false});

  final String content;
  final bool isError;

  Map<String, dynamic> toJson() => {'content': content, 'isError': isError};
}

/// The four tools the workspace agent gets. Everything else is a shell
/// command; nothing else is a tool.
final class WorkspaceTools {
  WorkspaceTools({
    required this.files,
    required this.shell,
    this.maxTimeout = const Duration(minutes: 10),
    this.defaultTimeout = const Duration(seconds: 30),
  });

  final WorkspaceFiles files;
  final ShellRunner shell;
  final Duration maxTimeout;
  final Duration defaultTimeout;

  static const String readFile = 'read_file';
  static const String writeFile = 'write_file';
  static const String editFile = 'edit_file';
  static const String runShell = 'shell';

  /// Shell always asks; file edits are covered by the mount table's rw/ro
  /// flag, so they do not need a second prompt.
  bool needsApproval(String name) => name == runShell;

  List<Map<String, dynamic>> schemas({bool background = true}) => [
    _function(
      readFile,
      '读取工作区或挂载点内的文件。文本按 UTF-8 返回；图片（png/jpg/webp/svg/heic 等）'
      '以图片内容返回，可直接查看。',
      {
        'path': _string(
          '文件的绝对路径，例如 /mnt/sillydraft/books/雾港来信/chapters/0001-雾港.md',
        ),
      },
      ['path'],
    ),
    _function(
      writeFile,
      '写入整个文件（覆盖）。给了 base_hash 时先校验当前内容，不一致就拒绝，避免覆盖用户刚改过的稿子。',
      {
        'path': _string('文件的绝对路径'),
        'text': _string('要写入的完整 UTF-8 文本'),
        'base_hash': _string('可选。读取时拿到的 hash；不匹配则拒绝写入'),
      },
      ['path', 'text'],
    ),
    _function(
      editFile,
      '精确替换文件中的一段文本。old_string 必须在文件中唯一出现；不唯一或找不到都会报错，不会猜。',
      {
        'path': _string('文件的绝对路径'),
        'old_string': _string('要替换的原文，带足够上下文以保证唯一'),
        'new_string': _string('替换后的文本'),
      },
      ['path', 'old_string', 'new_string'],
    ),
    _function(
      runShell,
      '在工作区的 rootfs 里执行 shell 命令。cwd 相对 /workspace；'
      '长任务用 run_in_background，不要用 &。',
      {
        'command': _string('要执行的命令'),
        'cwd': _string('可选。相对 /workspace 的目录，或绝对路径'),
        'timeout': {
          'type': 'integer',
          'description': '超时秒数，默认 30，最大 ${maxTimeout.inSeconds}',
        },
        if (background)
          'run_in_background': {
            'type': 'boolean',
            'description': '后台执行，立即返回任务 id；完成后会通知，不要轮询',
          },
      },
      ['command'],
    ),
  ];

  Future<ToolCallResult> call(String name, Map<String, dynamic> args) async {
    try {
      return switch (name) {
        readFile => await _read(args),
        writeFile => await _write(args),
        editFile => await _edit(args),
        runShell => await _shell(args),
        _ => ToolCallResult('未知工具：$name', isError: true),
      };
    } on WorkspaceException catch (e) {
      return ToolCallResult(
        jsonEncode({'error': e.message, 'code': e.runtimeType.toString()}),
        isError: true,
      );
    } on FormatException catch (e) {
      return ToolCallResult(
        jsonEncode({'error': e.message, 'code': 'bad_argument'}),
        isError: true,
      );
    } on UnsupportedError catch (e) {
      return ToolCallResult(
        jsonEncode({'error': e.message, 'code': 'unsupported'}),
        isError: true,
      );
    }
  }

  Future<ToolCallResult> _read(Map<String, dynamic> args) async {
    final path = _requireString(args, 'path');
    final result = await files.read(path);
    return ToolCallResult(jsonEncode(result.toJson()));
  }

  Future<ToolCallResult> _write(Map<String, dynamic> args) async {
    final path = _requireString(args, 'path');
    final text = _requireString(args, 'text');
    final baseHash = args['base_hash'] as String?;
    final result = await files.write(path, text, baseHash: baseHash);
    return ToolCallResult(jsonEncode(result.toJson()));
  }

  Future<ToolCallResult> _edit(Map<String, dynamic> args) async {
    final path = _requireString(args, 'path');
    final oldString = _requireString(args, 'old_string');
    final newString = _requireString(args, 'new_string');
    final result = await files.edit(
      path,
      oldString: oldString,
      newString: newString,
    );
    return ToolCallResult(jsonEncode(result.toJson()));
  }

  Future<ToolCallResult> _shell(Map<String, dynamic> args) async {
    final command = _requireString(args, 'command');
    final cwd = args['cwd'] as String? ?? '/workspace';
    final seconds = (args['timeout'] as num?)?.toInt();
    final timeout = seconds == null
        ? defaultTimeout
        : Duration(seconds: seconds.clamp(1, maxTimeout.inSeconds));
    final result = await shell.run(
      ShellRequest(
        command: command,
        cwd: cwd,
        timeout: timeout,
        background: args['run_in_background'] == true,
      ),
    );
    return ToolCallResult(jsonEncode(result.toJson()));
  }

  static String _requireString(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('缺少参数：$key');
    }
    return value;
  }

  static Map<String, dynamic> _function(
    String name,
    String description,
    Map<String, dynamic> properties,
    List<String> required,
  ) => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': properties,
        'required': required,
        'additionalProperties': false,
      },
    },
  };

  static Map<String, dynamic> _string(String description) => {
    'type': 'string',
    'description': description,
  };
}
