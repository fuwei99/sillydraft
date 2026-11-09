import 'package:sillydraft_workspace/sillydraft_workspace.dart';
import 'package:test/test.dart';

void main() {
  MountTable table() => MountTable([
    MountEntry(
      hostPath: '/data/app/files/workspace',
      guestPath: '/workspace',
      mode: MountMode.rw,
      label: 'workspace',
      builtIn: true,
    ),
    MountEntry(
      hostPath: '/storage/emulated/0/Documents/sillydraft',
      guestPath: '/mnt/sillydraft',
      mode: MountMode.rw,
      label: 'sillydraft',
      builtIn: true,
    ),
    MountEntry(
      hostPath: '/storage/emulated/0/Documents/refs',
      guestPath: '/mnt/refs',
      mode: MountMode.ro,
      label: 'refs',
    ),
  ]);

  test('names the workspace, the library and every extra mount', () {
    final prompt = buildWorkspacePrompt(table());
    expect(prompt, contains('- /workspace ——'));
    expect(prompt, contains('- /mnt/sillydraft ——'));
    expect(prompt, contains('- /mnt/refs ——'));
    expect(prompt, contains('（可写）'));
    expect(prompt, contains('（只读）'));
  });

  test('says that everything else does not exist', () {
    final prompt = buildWorkspacePrompt(table());
    expect(prompt, contains('只有上面这些路径存在'));
    expect(prompt, contains('/sdcard'));
    expect(prompt, contains('不要假设它们能访问'));
  });

  test('never leaks a host path', () {
    final prompt = buildWorkspacePrompt(table());
    expect(prompt, isNot(contains('/storage/emulated')));
    expect(prompt, isNot(contains('/data/app')));
  });

  test('wraps the block in a workspace tag', () {
    final prompt = buildWorkspacePrompt(table());
    expect(prompt.trimLeft(), startsWith('<workspace>'));
    expect(prompt.trimRight(), endsWith('</workspace>'));
  });

  test('mentions the current directory when one is given', () {
    final prompt = buildWorkspacePrompt(
      table(),
      cwd: '/mnt/sillydraft/books/雾港来信',
    );
    expect(prompt, contains('当前工作目录：/mnt/sillydraft/books/雾港来信'));
  });
}
