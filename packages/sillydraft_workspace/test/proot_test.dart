import 'package:sillydraft_workspace/sillydraft_workspace.dart';
import 'package:test/test.dart';

void main() {
  final table = MountTable.standard(
    workspaceHost: '/data/user/0/app/files/workspace',
    dataHost: '/storage/emulated/0/Documents/sillydraft',
  );

  final builder = ProotCommandBuilder(
    rootfsDir: '/data/user/0/app/files/rootfs',
    prootExecutable: '/data/app/lib/arm64/libproot_exec.so',
    loaderPath: '/data/app/lib/arm64/libproot_loader.so',
    tempDir: '/data/user/0/app/cache',
    hostWorkingDirectory: '/data/user/0/app/files',
  );

  test('binds every mount row and nothing else', () {
    final command = builder.build(table: table, command: 'ls /');
    final bindArgs = <String>[];
    for (var i = 0; i < command.args.length - 1; i++) {
      if (command.args[i] == '-b') bindArgs.add(command.args[i + 1]);
    }
    expect(
      bindArgs,
      containsAll([
        '/data/user/0/app/files/workspace:/workspace',
        '/storage/emulated/0/Documents/sillydraft:/mnt/sillydraft',
      ]),
    );
    expect(bindArgs.where((b) => b.contains('/sdcard')), isEmpty);
  });

  test('sets the rootfs and the guest cwd', () {
    final command = builder.build(table: table, command: 'pwd');
    expect(
      command.args,
      containsAllInOrder(['-r', '/data/user/0/app/files/rootfs']),
    );
    expect(command.args, containsAllInOrder(['-w', '/workspace']));
  });

  test('passes the command as a positional argument, unescaped', () {
    const evil = r'''echo "a b" | sed 's/a/c/'; echo $HOME''';
    final command = builder.build(table: table, command: evil);
    expect(command.args.last, evil);
    expect(command.args, contains(r'cd -- "$1" && eval "$2"'));
  });

  test('resolves a relative cwd against /workspace', () {
    final command = builder.build(
      table: table,
      command: 'pwd',
      cwd: 'books/雾港来信',
    );
    expect(command.args, containsAllInOrder(['-w', '/workspace/books/雾港来信']));
  });

  test('points PRoot at the loader and temp dir', () {
    final command = builder.build(table: table, command: 'true');
    expect(command.environment['PROOT_LOADER'], endsWith('libproot_loader.so'));
    expect(command.environment['PROOT_TMP_DIR'], '/data/user/0/app/cache');
    expect(command.environment['TMPDIR'], '/data/user/0/app/cache');
  });

  test('starts in the host working directory', () {
    final command = builder.build(table: table, command: 'true');
    expect(command.workingDirectory, '/data/user/0/app/files');
  });
}
