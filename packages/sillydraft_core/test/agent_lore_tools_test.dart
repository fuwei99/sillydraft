import 'dart:convert';

import 'package:sillydraft_core/sillydraft_core.dart';
import 'package:test/test.dart';

import 'task_runner_test.dart' show ScriptProvider;

final _model = ModelConnection(
  id: 'test',
  name: 'test',
  baseUrl: 'http://localhost:1',
  model: 'test',
);

Map<String, dynamic> _entry(Chapter chapter, {String name = '雾海'}) => {
  'kind': 'world',
  'name': name,
  'content': '雾海的潮汐由双月控制',
  'certainty': 'fact',
  'sourceChapterId': chapter.id,
};

ToolCallReady _save(List<Map<String, dynamic>> entries) =>
    ToolCallReady('save', 'save_lore', {'entries': entries});

Future<GenerationTask> _run(
  StoryRepository repo,
  Chapter through,
  Future<List<ProviderEvent>> Function(int round, Map result) step,
) async {
  final conversation = await repo.createConversation(
    branchId: through.branchId,
    throughChapterId: through.id,
    title: '整理资料',
  );
  var round = 0;
  final runner = TaskRunner(
    repository: repo,
    providerFactory: (c) async => ScriptProvider(c, (request, _) async* {
      if (round == 0) {
        expect(
          request.tools.map((t) => t['function']['name']),
          contains('save_lore'),
        );
      }
      final result = request.messages.last['role'] == 'tool'
          ? jsonDecode(request.messages.last['content'] as String) as Map
          : <String, dynamic>{};
      final events = await step(round++, result);
      yield* Stream.fromIterable(events);
      yield GenerationFinished(events.isEmpty ? 'stop' : 'tool_calls');
    }),
  );
  addTearDown(runner.close);
  final task = await EditorAgent(repository: repo, runner: runner).send(
    conversationId: conversation,
    connection: _model,
    message: '把小说人物和世界设定整理到资料里',
  );
  final done = await runner.wait(task.id);
  expect(done.status, TaskStatus.completed, reason: done.error);
  return done;
}

void main() {
  late StoryRepository repo;
  late Novel novel;
  late Chapter first;
  late Chapter later;
  setUp(() async {
    repo = StoryRepository.memory();
    addTearDown(() => repo.close());
    novel = await repo.createNovel(title: '导入的小说');
    first = await repo.createChapter(
      branchId: novel.activeBranchId,
      content: ManuscriptContent.plainText('林岚出海，双月升起。'),
    );
    later = await repo.createChapter(
      branchId: novel.activeBranchId,
      content: ManuscriptContent.plainText('林岚发现未来的秘密。'),
    );
  });

  test(
    'saves lore, reads live revisions and updates without changing prose',
    () async {
      final lin = await repo.saveLoreEntry(
        branchId: novel.activeBranchId,
        kind: LoreKind.character,
        name: '林岚',
        content: '水手',
        atChapterId: first.id,
        data: {'appearance': '短发', 'contextRequired': true, 'authorNote': '保留'},
      );
      await repo.saveLoreEntry(
        branchId: novel.activeBranchId,
        kind: LoreKind.world,
        name: '未来秘密',
        content: '尚未读到',
        atChapterId: later.id,
      );
      String? worldId, worldRevision;
      final task = await _run(repo, first, (round, result) async {
        switch (round) {
          case 0:
            return [
              _save([_entry(first)]),
            ];
          case 1:
            final saved = (result['results'] as List).single as Map;
            expect(saved['error'], isNull);
            worldId = saved['id'] as String;
            worldRevision = saved['revisionId'] as String;
            return [ToolCallReady('list', 'list_lore', {})];
          case 2:
            expect((result['entries'] as List).map((e) => e['name']), [
              '林岚',
              '雾海',
            ]);
            return [
              ToolCallReady('read', 'read_lore', {'id': worldId}),
            ];
          case 3:
            expect(result['revisionId'], worldRevision);
            expect(result['content'], '雾海的潮汐由双月控制');
            return [
              _save([
                {
                  ..._entry(first),
                  'id': worldId,
                  'expectedRevisionId': worldRevision,
                  'content': '双月引发大潮',
                },
                {
                  ..._entry(first, name: lin.name),
                  'kind': 'character',
                  'id': lin.id,
                  'expectedRevisionId': lin.revisionId,
                  'content': '出海的水手',
                  'outfit': '蓑衣',
                },
              ]),
            ];
          case 4:
            expect((result['results'] as List).map((r) => r['error']), [
              null,
              null,
            ]);
            return [
              ToolCallReady('read', 'read_lore', {'id': worldId}),
            ];
          default:
            expect(result['revisionId'], isNot(worldRevision));
            expect(result['content'], '双月引发大潮');
            return [];
        }
      });
      final saved = await repo.getLoreEntry(
        branchId: novel.activeBranchId,
        id: worldId!,
      );
      expect(saved.atChapterId, first.id);
      expect(saved.provenance, {
        'type': 'editor',
        'taskId': task.id,
        'chapterId': first.id,
        'revisionId': first.revisionId,
      });
      final updated = await repo.getLoreEntry(
        branchId: novel.activeBranchId,
        id: lin.id,
      );
      expect(updated.data, {...lin.data, 'outfit': '蓑衣'});
      expect(
        (await repo.getStory(novel.activeBranchId)).chapters
            .map((c) => c.revisionId),
        [first.revisionId, later.revisionId],
      );
      expect(
        (await repo.listTasks()).where((t) => t.kind == TaskKind.analysis),
        isEmpty,
      );
    },
  );

  test(
    'rejects duplicate creates, stale updates and world book edits per entry',
    () async {
      final existing = await repo.saveLoreEntry(
        branchId: first.branchId,
        kind: LoreKind.world,
        name: '雾海',
        content: '作者设定',
        atChapterId: first.id,
      );
      final book = await repo.saveLoreEntry(
        branchId: first.branchId,
        kind: LoreKind.world,
        name: '世界书',
        content: '世界书快照',
        atChapterId: first.id,
        data: {'worldBookOnly': true},
      );
      await _run(repo, first, (round, result) async {
        if (round == 0) {
          await repo.saveLoreEntry(
            branchId: first.branchId,
            kind: existing.kind,
            id: existing.id,
            expectedRevisionId: existing.revisionId,
            name: existing.name,
            content: '作者刚刚修改',
            atChapterId: first.id,
          );
          return [
            _save([
              _entry(first),
              {
                ..._entry(first),
                'id': existing.id,
                'expectedRevisionId': existing.revisionId,
              },
              {
                ..._entry(first, name: book.name),
                'id': book.id,
                'expectedRevisionId': book.revisionId,
              },
              _entry(first, name: '可保存的新设定'),
            ]),
          ];
        }
        final results = (result['results'] as List).cast<Map>();
        expect(results[0]['error'], contains('同名'));
        expect(results[1]['error'], contains('版本冲突'));
        expect(results[2]['error'], contains('世界书'));
        expect(results[3]['error'], isNull);
        return [];
      });
      expect(
        (await repo.getLoreEntry(
          branchId: first.branchId,
          id: existing.id,
        )).content,
        '作者刚刚修改',
      );
      expect(
        (await repo.getLoreEntry(
          branchId: first.branchId,
          id: book.id,
        )).revisionId,
        book.revisionId,
      );
      expect((await repo.listLore(first.branchId)).length, 3);
    },
  );

  test(
    'validates sources, branch scope and kind fields before saving',
    () async {
      final other = await repo.createNovel(title: '另一本书');
      final foreign = await repo.createChapter(branchId: other.activeBranchId);
      final hidden = await repo.saveLoreEntry(
        branchId: first.branchId,
        kind: LoreKind.world,
        name: '未来',
        content: '秘密',
        atChapterId: later.id,
      );
      await _run(repo, first, (round, result) async {
        if (round == 0) {
          return [
            _save([
              {..._entry(first)}..remove('sourceChapterId'),
              _entry(later),
              _entry(foreign),
              {
                ..._entry(first),
                'id': hidden.id,
                'expectedRevisionId': hidden.revisionId,
              },
              {..._entry(first), 'kind': 'map'},
              {..._entry(first), 'fromId': 'invalid'},
              {..._entry(first), 'certainty': 'unknown'},
            ]),
          ];
        }
        expect(
          (result['results'] as List).map((r) => r['error']),
          everyElement(isA<String>()),
        );
        return [];
      });
      expect((await repo.listLore(first.branchId)).single.id, hidden.id);
    },
  );

  test('organizes multiple chapters and links saved entities without future leakage', () async {
    String? personId, personRevision, locationId;
    await _run(repo, later, (round, result) async {
      if (round == 0) {
        return [
          _save([
            {
              ..._entry(first, name: '林岚'),
              'kind': 'character',
              'content': '水手',
            },
            {..._entry(first), 'kind': 'location'},
          ]),
        ];
      }
      if (round == 1) {
        final results = (result['results'] as List).cast<Map>();
        personId = results[0]['id'] as String;
        personRevision = results[0]['revisionId'] as String;
        locationId = results[1]['id'] as String;
        return [
          _save([
            {
              ..._entry(later, name: '林岚'),
              'kind': 'character',
              'id': personId,
              'expectedRevisionId': personRevision,
              'content': '发现双月秘密的水手',
            },
            {
              ..._entry(later, name: '林岚探索雾海'),
              'kind': 'relationship',
              'fromId': personId,
              'toId': locationId,
              'directed': true,
            },
          ]),
        ];
      }
      expect((result['results'] as List).map((r) => r['error']), [null, null]);
      return [];
    });
    final before = await repo.listLore(
      first.branchId,
      throughChapterId: first.id,
    );
    expect(before, hasLength(2));
    expect(before.singleWhere((e) => e.id == personId).content, '水手');
    final after = await repo.listLore(first.branchId);
    expect(after.singleWhere((e) => e.id == personId).content, '发现双月秘密的水手');
    final relation = after.singleWhere((e) => e.kind == LoreKind.relationship);
    expect(relation.data, {
      'fromId': personId,
      'toId': locationId,
      'directed': true,
    });
    expect(relation.atChapterId, later.id);
  });

  test(
    'cannot bypass a newer visible lore revision by using an earlier source',
    () async {
      final old = await repo.saveLoreEntry(
        branchId: first.branchId,
        kind: LoreKind.world,
        name: '雾海',
        content: '第一章设定',
        atChapterId: first.id,
      );
      final latest = await repo.saveLoreEntry(
        branchId: first.branchId,
        id: old.id,
        expectedRevisionId: old.revisionId,
        kind: old.kind,
        name: old.name,
        content: '后续设定',
        atChapterId: later.id,
      );
      Object? error;
      await _run(repo, later, (round, result) async {
        if (round == 0) {
          return [
            _save([
              {
                ..._entry(first),
                'id': old.id,
                'expectedRevisionId': old.revisionId,
              },
            ]),
          ];
        }
        error = (result['results'] as List).single['error'];
        return [];
      });
      expect(error, contains('版本冲突'));
      expect(
        (await repo.getLoreEntry(
          branchId: first.branchId,
          id: old.id,
          throughChapterId: first.id,
        )).revisionId,
        old.revisionId,
      );
      expect(
        (await repo.getLoreEntry(
          branchId: first.branchId,
          id: old.id,
        )).revisionId,
        latest.revisionId,
      );
    },
  );

  test(
    'changed chapter stops saving and subsequent writes in the turn',
    () async {
      await _run(repo, first, (round, result) async {
        if (round == 0) {
          await repo.saveChapter(
            branchId: first.branchId,
            chapterId: first.id,
            expectedRevisionId: first.revisionId,
            content: ManuscriptContent.plainText('作者修改过正文'),
          );
          return [
            _save([_entry(first)]),
          ];
        }
        if (round == 1) {
          expect(result['code'], 'source_changed');
          return [
            _save([_entry(first, name: '不应写入')]),
          ];
        }
        expect(result['code'], 'writing_stopped');
        return [];
      });
      expect(await repo.listLore(first.branchId), isEmpty);
    },
  );

  test('cancellation keeps saved lore and stops subsequent writes', () async {
    final conversation = await repo.createConversation(
      branchId: first.branchId,
      throughChapterId: first.id,
      title: '整理资料',
    );
    var round = 0;
    final runner = TaskRunner(
      repository: repo,
      providerFactory: (c) async => ScriptProvider(c, (request, cancel) async* {
        if (round++ == 0) {
          yield _save([_entry(first)]);
        } else {
          cancel.cancel();
          yield _save([_entry(first, name: '不应保存')]);
        }
        yield const GenerationFinished('tool_calls');
      }),
    );
    addTearDown(runner.close);
    final task = await EditorAgent(
      repository: repo,
      runner: runner,
    ).send(conversationId: conversation, connection: _model, message: '整理资料');
    expect((await runner.wait(task.id)).status, TaskStatus.cancelled);
    expect((await repo.listLore(first.branchId)).single.name, '雾海');
  });
}
