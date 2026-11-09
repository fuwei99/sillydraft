import 'dart:convert';
import 'dart:io';

import 'package:sillydraft_workspace/sillydraft_workspace.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late MountTable table;
  late WorkspaceTools tools;

  setUp(() {
    root = Directory.systemTemp.createTempSync('sdw_tools_');
    final workspace = Directory('${root.path}/workspace')..createSync();
    final data = Directory('${root.path}/Documents/sillydraft')
      ..createSync(recursive: true);
    table = MountTable.standard(
      workspaceHost: workspace.path,
      dataHost: data.path,
    );
    tools = WorkspaceTools(
      files: WorkspaceFiles(table),
      shell: HostShellRunner(table),
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('exposes exactly four tools', () {
    final names = tools
        .schemas()
        .map((s) => (s['function'] as Map<String, dynamic>)['name'])
        .toList();
    expect(names, ['read_file', 'write_file', 'edit_file', 'shell']);
  });

  test('shell needs approval, file edits do not', () {
    expect(tools.needsApproval('shell'), isTrue);
    expect(tools.needsApproval('write_file'), isFalse);
    expect(tools.needsApproval('edit_file'), isFalse);
  });

  test('write then read through the dispatcher', () async {
    final write = await tools.call('write_file', {
      'path': '/mnt/sillydraft/books/a/chapters/0001.md',
      'text': '# 第一章\n',
    });
    expect(write.isError, isFalse);
    expect(
      jsonDecode(write.content)['path'],
      '/mnt/sillydraft/books/a/chapters/0001.md',
    );

    final read = await tools.call('read_file', {
      'path': '/mnt/sillydraft/books/a/chapters/0001.md',
    });
    expect(read.isError, isFalse);
    expect(jsonDecode(read.content)['text'], '# 第一章\n');
  });

  test('a rejected write comes back as an error result, not a throw', () async {
    final result = await tools.call('write_file', {
      'path': '/mnt/sillydraft/../../etc/passwd',
      'text': 'x',
    });
    expect(result.isError, isTrue);
    final body = jsonDecode(result.content) as Map<String, dynamic>;
    expect(body['code'], 'OutsideWorkspaceException');
  });

  test('shell runs in the workspace by default', () async {
    final result = await tools.call('shell', {'command': 'pwd'});
    expect(result.isError, isFalse);
    final body = jsonDecode(result.content) as Map<String, dynamic>;
    expect(body['exitCode'], 0);
    expect(body['stdout'].toString().trim(), '${root.path}/workspace');
  });

  test('shell reports a non-zero exit code', () async {
    final result = await tools.call('shell', {'command': 'exit 3'});
    final body = jsonDecode(result.content) as Map<String, dynamic>;
    expect(body['exitCode'], 3);
  });

  test('shell can read the library through its mount', () async {
    await tools.call('write_file', {
      'path': '/mnt/sillydraft/hello.md',
      'text': 'hi',
    });
    final result = await tools.call('shell', {
      'command': 'cat hello.md',
      'cwd': '/mnt/sillydraft',
    });
    final body = jsonDecode(result.content) as Map<String, dynamic>;
    expect(body['stdout'], 'hi');
  });

  test('unknown tools fail cleanly', () async {
    final result = await tools.call('rm_rf', {});
    expect(result.isError, isTrue);
  });
}
