import 'mounts.dart';
import 'paths.dart';

/// The `<workspace>` block prepended to the assistant's system prompt.
///
/// It names every guest path the model may touch and says, in as many words,
/// that everything else does not exist. The mount list is generated from the
/// table, so the prompt cannot drift from what is actually mounted.
String buildWorkspacePrompt(
  MountTable table, {
  String distro = 'Ubuntu 24.04',
  String shell = '/bin/sh',
  String? cwd,
}) {
  final ordered = [...table.entries]
    ..sort((a, b) {
      int rank(MountEntry entry) => switch (entry.guestPath) {
        WorkspacePaths.workspace => 0,
        WorkspacePaths.data => 1,
        _ => 2,
      };
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.guestPath.compareTo(b.guestPath);
    });

  final buffer = StringBuffer()
    ..writeln('<workspace>')
    ..writeln(
      '你可以在这台安卓设备上的一个 Linux 工作区里执行命令、读写文件。'
      '它运行在 $distro 的 proot rootfs（$shell）中；设备上除了下面列出的挂载点，其他路径都不存在。',
    )
    ..writeln()
    ..writeln('路径：');

  for (final entry in ordered) {
    buffer.writeln(
      '- ${entry.guestPath} —— ${_describe(entry)}（${entry.writable ? '可写' : '只读'}）',
    );
  }

  buffer
    ..writeln()
    ..writeln(
      '只有上面这些路径存在。/sdcard、/storage、/data、/system 之类没有被挂载，'
      '不要假设它们能访问，也不要尝试通过 /proc 绕过。',
    )
    ..writeln()
    ..writeln('规则：')
    ..writeln('- 所有工具都用绝对路径；相对路径按 ${WorkspacePaths.workspace} 解析。')
    ..writeln('- 改文件前先读。用户可能在应用外改过，读到的才是最新的；不要盲目覆盖。')
    ..writeln(
      '- 搜索、批量处理、版本操作优先用 shell（ls、find、grep、sed、git）；'
      '精确修改用 edit_file，整文件重写用 write_file。',
    )
    ..writeln(
      '- 保持书库结构：books/<书名>/chapters/0001-标题.md、lore/、assets/、presets/、'
      'worldbooks/、cards/。不要发明新的顶层目录。',
    )
    ..writeln('- 不要在 ${WorkspacePaths.workspace} 和上述挂载点之外创建文件。');

  if (cwd != null && cwd.isNotEmpty) {
    buffer.writeln('- 当前工作目录：$cwd。');
  }

  buffer.writeln('</workspace>');
  return buffer.toString();
}

String _describe(MountEntry entry) => switch (entry.guestPath) {
  WorkspacePaths.workspace => '你的工作区。脚本、草稿、临时文件放这里；跨轮次保留，但不是用户的资料库',
  WorkspacePaths.data =>
    '用户的 SillyDraft 数据：书籍、章节、设定、预设、世界书、角色卡和插图。'
        '这是唯一的事实来源，直接改这里',
  _ => '用户额外挂载的目录「${entry.label}」',
};
