import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sillydraft_workspace/sillydraft_workspace.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory workspace;
  late Directory data;
  late MountTable table;
  late WorkspaceFiles files;

  setUp(() {
    root = Directory.systemTemp.createTempSync('sdw_files_');
    workspace = Directory('${root.path}/workspace')..createSync();
    data = Directory('${root.path}/Documents/sillydraft')
      ..createSync(recursive: true);
    table = MountTable.standard(
      workspaceHost: workspace.path,
      dataHost: data.path,
    );
    files = WorkspaceFiles(table);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('writes and reads a chapter', () async {
    final written = await files.write(
      '/mnt/sillydraft/books/雾港来信/chapters/0001-雾港.md',
      '# 第一章\n\n海雾压着码头。\n',
    );
    expect(written.byteLength, greaterThan(0));
    expect(written.hash, hasLength(64));

    final read = await files.read(
      '/mnt/sillydraft/books/雾港来信/chapters/0001-雾港.md',
    );
    expect(read.text, '# 第一章\n\n海雾压着码头。\n');
    expect(read.isImage, isFalse);
  });

  test('leaves no temporary file behind', () async {
    await files.write('/mnt/sillydraft/a.md', 'x');
    final names = data.listSync().map((e) => e.path.split('/').last).toList();
    expect(names.where((n) => n.endsWith('.tmp')), isEmpty);
  });

  test('refuses to overwrite a file that changed since it was read', () async {
    await files.write('/mnt/sillydraft/a.md', 'first');
    final before = sha256.convert('first'.codeUnits).toString();

    await files.write('/mnt/sillydraft/a.md', 'user edit');

    expect(
      () => files.write('/mnt/sillydraft/a.md', 'agent edit', baseHash: before),
      throwsA(isA<ContentConflict>()),
    );
  });

  test('accepts a matching base hash', () async {
    final written = await files.write('/mnt/sillydraft/a.md', 'first');
    final again = await files.write(
      '/mnt/sillydraft/a.md',
      'second',
      baseHash: written.hash,
    );
    expect(again.hash, sha256.convert('second'.codeUnits).toString());
  });

  test('edit replaces exactly one occurrence', () async {
    await files.write('/mnt/sillydraft/a.md', '海雾压着码头。\n她没回头。\n');
    final result = await files.edit(
      '/mnt/sillydraft/a.md',
      oldString: '她没回头。',
      newString: '她还是回了头。',
    );
    expect(result.byteLength, greaterThan(0));
    expect(
      (await files.read('/mnt/sillydraft/a.md')).text,
      '海雾压着码头。\n她还是回了头。\n',
    );
  });

  test('edit refuses a missing target', () async {
    await files.write('/mnt/sillydraft/a.md', 'abc');
    expect(
      () =>
          files.edit('/mnt/sillydraft/a.md', oldString: 'zzz', newString: 'y'),
      throwsA(isA<EditTargetNotFound>()),
    );
  });

  test('edit refuses an ambiguous target', () async {
    await files.write('/mnt/sillydraft/a.md', '回声。\n回声。\n');
    expect(
      () => files.edit(
        '/mnt/sillydraft/a.md',
        oldString: '回声。',
        newString: '沉默。',
      ),
      throwsA(isA<AmbiguousEdit>()),
    );
  });

  test('read-only mount cannot be written', () async {
    final readOnly = MountTable([
      MountEntry(
        hostPath: workspace.path,
        guestPath: '/workspace',
        mode: MountMode.rw,
      ),
      MountEntry(
        hostPath: data.path,
        guestPath: '/mnt/sillydraft',
        mode: MountMode.ro,
      ),
    ]);
    expect(
      () => WorkspaceFiles(readOnly).write('/mnt/sillydraft/a.md', 'x'),
      throwsA(isA<ReadOnlyMountException>()),
    );
  });

  test('a symlink cannot walk out of its mount', () async {
    final outside = Directory('${root.path}/outside')..createSync();
    File('${outside.path}/secret.txt').writeAsStringSync('nope');
    Link('${data.path}/escape').createSync(outside.path);

    expect(
      () => files.read('/mnt/sillydraft/escape/secret.txt'),
      throwsA(isA<OutsideWorkspaceException>()),
    );
  });

  test('images come back as bytes with a mime type', () async {
    final bytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];
    File('${data.path}/cover.png').writeAsBytesSync(bytes);
    final read = await files.read('/mnt/sillydraft/cover.png');
    expect(read.isImage, isTrue);
    expect(read.mimeType, 'image/png');
    expect(read.bytes, bytes);
  });

  test('rejects files above the read limit', () async {
    File('${data.path}/big.md').writeAsStringSync('x' * 100);
    expect(
      () => files.read('/mnt/sillydraft/big.md', maxBytes: 10),
      throwsA(isA<GuestFileTooLarge>()),
    );
  });

  test('rejects a missing file', () async {
    expect(
      () => files.read('/mnt/sillydraft/nope.md'),
      throwsA(isA<GuestFileNotFound>()),
    );
  });
}
