import 'dart:io';

import 'package:sillydraft_workspace/sillydraft_workspace.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late MountTable table;
  late HostShellRunner runner;

  setUp(() {
    root = Directory.systemTemp.createTempSync('sdw_shell_');
    final workspace = Directory('${root.path}/workspace')..createSync();
    final data = Directory('${root.path}/Documents/sillydraft')
      ..createSync(recursive: true);
    table = MountTable.standard(
      workspaceHost: workspace.path,
      dataHost: data.path,
    );
    runner = HostShellRunner(table);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('captures stdout, stderr and the exit code', () async {
    final result = await runner.run(
      const ShellRequest(command: 'echo out; echo err >&2; exit 7'),
    );
    expect(result.stdout.trim(), 'out');
    expect(result.stderr.trim(), 'err');
    expect(result.exitCode, 7);
    expect(result.timedOut, isFalse);
  });

  test('runs in the requested guest directory', () async {
    final result = await runner.run(
      const ShellRequest(command: 'pwd', cwd: '/mnt/sillydraft'),
    );
    expect(result.stdout.trim(), '${root.path}/Documents/sillydraft');
  });

  test('relative cwd resolves against /workspace', () async {
    Directory('${root.path}/workspace/books').createSync();
    final result = await runner.run(
      const ShellRequest(command: 'pwd', cwd: 'books'),
    );
    expect(result.stdout.trim(), '${root.path}/workspace/books');
  });

  test('a mount outside the table is not reachable', () async {
    final result = await runner.run(const ShellRequest(command: 'ls /sdcard'));
    expect(result.exitCode, isNot(0));
  });

  test('times out and says so', () async {
    final result = await runner.run(
      const ShellRequest(
        command: 'sleep 5',
        timeout: Duration(milliseconds: 150),
      ),
    );
    expect(result.timedOut, isTrue);
  });

  test('truncates huge output but keeps both ends', () async {
    final small = HostShellRunner(table, maxOutputBytes: 200);
    final result = await small.run(const ShellRequest(command: 'seq 1 5000'));
    expect(result.truncated, isTrue);
    expect(result.stdout, contains('1\n2'));
    expect(result.stdout, contains('5000'));
    expect(result.stdout.length, lessThan(400));
  });
}
