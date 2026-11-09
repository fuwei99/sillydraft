import 'package:sillydraft_workspace/sillydraft_workspace.dart';
import 'package:test/test.dart';

void main() {
  MountTable standard() => MountTable.standard(
    workspaceHost: '/data/app/files/workspace',
    dataHost: '/storage/emulated/0/Documents/sillydraft',
  );

  group('MountTable', () {
    test('a fresh table has exactly the workspace and the library', () {
      final table = standard();
      expect(
        table.entries.map((e) => e.guestPath),
        unorderedEquals(['/workspace', '/mnt/sillydraft']),
      );
      expect(table.entries.every((e) => e.writable), isTrue);
    });

    test('resolves a file below the library mount', () {
      final resolved = standard().resolve(
        '/mnt/sillydraft/books/雾港来信/chapters/0001-雾港.md',
      );
      expect(
        resolved.hostPath,
        '/storage/emulated/0/Documents/sillydraft/books/雾港来信/chapters/0001-雾港.md',
      );
      expect(resolved.entry.guestPath, '/mnt/sillydraft');
      expect(resolved.writable, isTrue);
    });

    test('resolves the mount root itself', () {
      final resolved = standard().resolve('/mnt/sillydraft');
      expect(resolved.relativePath, '');
      expect(resolved.hostPath, '/storage/emulated/0/Documents/sillydraft');
    });

    test('normalizes duplicate slashes and dot segments', () {
      final resolved = standard().resolve(
        '/mnt//sillydraft/./books/../books/a.md',
      );
      expect(
        resolved.hostPath,
        '/storage/emulated/0/Documents/sillydraft/books/a.md',
      );
    });

    test('rejects paths outside every mount', () {
      expect(
        () => standard().resolve('/sdcard/DCIM/a.jpg'),
        throwsA(isA<OutsideWorkspaceException>()),
      );
      expect(
        () => standard().resolve('/mnt/other/a.md'),
        throwsA(isA<OutsideWorkspaceException>()),
      );
    });

    test('rejects traversal above the root', () {
      expect(
        () => standard().resolve('/../../etc/passwd'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects mounts that expose the device or system', () {
      for (final host in [
        '/sdcard',
        '/storage',
        '/storage/emulated/0',
        '/data',
        '/',
      ]) {
        expect(
          () => MountTable([
            MountEntry(
              hostPath: '/data/app/files/workspace',
              guestPath: '/workspace',
              mode: MountMode.rw,
            ),
            MountEntry(hostPath: host, guestPath: '/mnt/x', mode: MountMode.ro),
          ]),
          throwsA(isA<FormatException>()),
          reason: host,
        );
      }
    });

    test('rejects a guest outside /mnt', () {
      expect(
        () => MountTable([
          MountEntry(
            hostPath: '/data/app/files/workspace',
            guestPath: '/workspace',
            mode: MountMode.rw,
          ),
          MountEntry(
            hostPath: '/storage/emulated/0/Documents/x',
            guestPath: '/opt/x',
          ),
        ]),
        throwsA(isA<FormatException>()),
      );
    });

    test('longest guest prefix wins', () {
      final table = MountTable([
        MountEntry(
          hostPath: '/data/app/files/workspace',
          guestPath: '/workspace',
          mode: MountMode.rw,
        ),
        MountEntry(
          hostPath: '/storage/emulated/0/Documents/sillydraft',
          guestPath: '/mnt/sillydraft',
          mode: MountMode.rw,
        ),
        MountEntry(
          hostPath: '/storage/emulated/0/Documents/refs',
          guestPath: '/mnt/sillydraft/refs',
          mode: MountMode.ro,
        ),
      ]);
      expect(
        table.resolve('/mnt/sillydraft/refs/a.md').hostPath,
        '/storage/emulated/0/Documents/refs/a.md',
      );
      expect(
        table.resolve('/mnt/sillydraft/books/a.md').hostPath,
        '/storage/emulated/0/Documents/sillydraft/books/a.md',
      );
    });

    test('read-only mounts refuse writes', () {
      final table = MountTable([
        MountEntry(
          hostPath: '/data/app/files/workspace',
          guestPath: '/workspace',
          mode: MountMode.rw,
        ),
        MountEntry(
          hostPath: '/storage/emulated/0/Documents/refs',
          guestPath: '/mnt/refs',
          mode: MountMode.ro,
        ),
      ]);
      expect(
        () => table.resolveForWrite('/mnt/refs/a.md'),
        throwsA(isA<ReadOnlyMountException>()),
      );
    });

    test('round-trips through JSON', () {
      final table = standard();
      final restored = MountTable.fromJson(
        workspaceHost: '/data/app/files/workspace',
        json: table.toJson(),
      );
      expect(
        restored.entries.map((e) => e.guestPath),
        unorderedEquals(['/workspace', '/mnt/sillydraft']),
      );
    });
  });
}
