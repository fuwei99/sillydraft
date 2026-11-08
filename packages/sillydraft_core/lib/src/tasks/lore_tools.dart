part of 'task_runner.dart';

/// The data fields lore tools may write per kind. Anything else an entry
/// holds (portraits, map points) is the author's and kept as it is.
const _loreFields = {
  LoreKind.character: ['appearance', 'outfit', 'goal', 'state', 'user'],
  LoreKind.relationship: ['fromId', 'toId', 'directed'],
  LoreKind.event: ['storyTime', 'status'],
  LoreKind.foreshadow: ['storyTime', 'status'],
};
const _loreFlags = {'user', 'directed'};

Map<String, dynamic> _saveLoreTool(Set<LoreKind> kinds) => _sidecarFunction(
  'save_lore',
  '批量新建或更新资料，直接写入并归于本章。更新须给 id 与 expectedRevisionId，未给出的字段保持原值。单次最多 20 条，逐条返回结果。',
  {
    'entries': {
      'type': 'array',
      'maxItems': 20,
      'items': {
        'type': 'object',
        'properties': {
          'id': {'type': 'string', 'description': '更新已有条目时填写'},
          'expectedRevisionId': {
            'type': 'string',
            'description': '更新时填读到的 revisionId',
          },
          'kind': {
            'type': 'string',
            'enum': [
              for (final k in LoreKind.values)
                if (kinds.contains(k)) k.name,
            ],
          },
          'name': {'type': 'string'},
          'content': {'type': 'string'},
          'certainty': {
            'type': 'string',
            'enum': [for (final c in LoreCertainty.values) c.name],
          },
          'appearance': {
            'type': 'string',
            'description':
                '人物：有依据的可见外貌与辨识特征，不含服饰、性格、情绪或动作。未知时省略以保留已有值，不写默认设定等占位语。',
          },
          'outfit': {
            'type': 'string',
            'description': '人物：有依据的当前服饰与配饰。未知时省略以保留已有值，不写占位语。',
          },
          'goal': {'type': 'string', 'description': '人物：动机与目标'},
          'state': {'type': 'string', 'description': '人物：当前状态，如伤势、情绪、处境'},
          'user': {'type': 'boolean', 'description': '人物：是否为主角 {{user}}'},
          'fromId': {'type': 'string', 'description': '关系：起点条目 id'},
          'toId': {'type': 'string', 'description': '关系：终点条目 id'},
          'directed': {'type': 'boolean', 'description': '关系：是否有方向'},
          'storyTime': {'type': 'string', 'description': '事件、伏笔：故事内时间'},
          'status': {
            'type': 'string',
            'enum': [
              'active',
              'planted',
              'developing',
              'resolved',
              'abandoned',
            ],
          },
        },
        'required': ['kind', 'name', 'content', 'certainty'],
        'additionalProperties': false,
      },
    },
  },
  ['entries'],
);

extension _LoreTools on TaskRunner {
  /// Writes one `save_lore` entry, answering with its new revision or why
  /// it was not written; one bad entry never stops the rest.
  Future<Map<String, dynamic>> _saveLore(
    GenerationTask task,
    int index,
    Object? value,
  ) async {
    LoreEntry? previous;
    try {
      final args = jsonObject(value, 'entry');
      final kind = LoreKind.values.asNameMap()[args['kind']];
      final certainty = LoreCertainty.values.asNameMap()[args['certainty']];
      final name = args['name'], content = args['content'];
      final id = args['id'], expected = args['expectedRevisionId'];
      if (kind == null ||
          certainty == null ||
          name is! String ||
          content is! String ||
          (id == null) != (expected == null) ||
          (id != null && (id is! String || expected is! String))) {
        throw const FormatException(
          'kind、certainty、name、content 无效，或更新缺少 id 与 expectedRevisionId',
        );
      }
      final fields = _loreFields[kind] ?? const <String>[];
      const common = {
        'id',
        'expectedRevisionId',
        'kind',
        'name',
        'content',
        'certainty',
      };
      if (args.keys.any((k) => !common.contains(k) && !fields.contains(k))) {
        throw FormatException('${kind.name} 条目只能写这些字段：${fields.join('、')}');
      }
      final given = {
        for (final key in fields)
          if (args.containsKey(key)) key: args[key],
      };
      if (given.entries.any(
        (e) =>
            _loreFlags.contains(e.key) ? e.value is! bool : e.value is! String,
      )) {
        throw const FormatException('字段类型无效');
      }
      previous = id == null
          ? null
          : await repository.getLoreEntry(
              branchId: task.branchId,
              id: id as String,
              throughChapterId: task.chapterId,
            );
      if (!_sidecarAllows(_sidecarDuties(task), kind, certainty, previous)) {
        throw FormatException('当前开启的职责不能写入 ${kind.name}（${certainty.name}）');
      }
      final saved = await repository.saveLoreEntry(
        branchId: task.branchId,
        id: id as String?,
        expectedRevisionId: expected as String?,
        kind: kind,
        name: name,
        content: content,
        certainty: certainty,
        atChapterId: task.chapterId,
        data: {...?previous?.data, ...given},
        provenance: _sidecarProvenance(task),
      );
      return {'index': index, 'id': saved.id, 'revisionId': saved.revisionId};
    } on LoreConflict {
      return {
        'index': index,
        'error': '版本冲突：资料已被修改，请重新读取后再写',
        'revisionId': ?previous?.revisionId,
      };
    } on FormatException catch (e) {
      return {'index': index, 'error': e.message};
    } on StoryNotFound {
      return {'index': index, 'error': '目标条目不存在或不在本章可见范围内'};
    } catch (e) {
      return {'index': index, 'error': '写入失败：$e'};
    }
  }
}
