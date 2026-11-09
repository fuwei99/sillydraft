import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/chapter_title.dart';
import '../model/manuscript.dart';
import '../model/story.dart';
import '../storage/story_repository.dart';

/// The library as plain files under `Documents/sillydraft`.
///
/// Chapters are Markdown with a small HTML-comment header (id, revision,
/// title); everything else is JSON. The database stays the working store,
/// but every export makes the files complete, and [importChanged] turns
/// edits made outside the app into new revisions.
final class LibraryFiles {
  LibraryFiles({required this.repository, required this.root});

  final StoryRepository repository;
  final Directory root;

  Future<void> exportAll() async {
    final novels = await repository.listNovels(includeArchived: true);
    for (final novel in novels) {
      if (novel.archived) continue;
      await exportNovel(novel);
    }
  }

  /// Rewrites only chapters whose database revision is newer than the file,
  /// so an edit the model made in the file is not overwritten.
  Future<void> exportChanged() async {
    final novels = await repository.listNovels(includeArchived: true);
    for (final novel in novels) {
      if (novel.archived) continue;
      await exportNovel(novel, onlyNewer: true);
    }
  }

  Future<void> exportNovel(Novel novel, {bool onlyNewer = false}) async {
    final story = await repository.getStory(novel.activeBranchId);
    final bookDir = Directory(p.join(root.path, 'books', _slug(novel.title)));
    await bookDir.create(recursive: true);
    await _writeJson(p.join(bookDir.path, 'novel.json'), {
      'id': novel.id,
      'title': novel.title,
      'synopsis': novel.synopsis,
      'genre': novel.genre,
      'language': novel.language,
      'style': novel.style,
      'pointOfView': novel.pointOfView,
      'activeBranchId': novel.activeBranchId,
      'chapterNumerals': novel.chapterNumerals.name,
      'createdAt': novel.createdAt.toIso8601String(),
      'updatedAt': novel.updatedAt.toIso8601String(),
    });

    final branchDir = Directory(
      p.join(bookDir.path, 'branches', _slug(story.branch.name)),
    );
    await branchDir.create(recursive: true);
    await _writeJson(p.join(branchDir.path, 'branch.json'), {
      'id': story.branch.id,
      'name': story.branch.name,
      'novelId': story.branch.novelId,
      'parentBranchId': story.branch.parentBranchId,
      'forkChapterId': story.branch.forkChapterId,
      'createdAt': story.branch.createdAt.toIso8601String(),
    });

    final chapterDir = Directory(p.join(branchDir.path, 'chapters'));
    await chapterDir.create(recursive: true);
    for (final chapter in story.chapters) {
      final number = (chapter.position + 1).toString().padLeft(4, '0');
      final title = _chapterTitle(chapter);
      final file = File(p.join(chapterDir.path, '$number-${_slug(title)}.md'));
      if (onlyNewer && await file.exists()) {
        final revision = await repository.getRevision(chapter.revisionId);
        if (!revision.createdAt.isAfter(await file.lastModified())) {
          continue;
        }
      }
      await file.writeAsString(_chapterFile(chapter, title));
    }

    final lore = await repository.listLore(novel.activeBranchId);
    await _writeJson(p.join(branchDir.path, 'lore.json'), [
      for (final entry in lore)
        if (!entry.deleted)
          {
            'id': entry.id,
            'revision': entry.revisionId,
            'kind': entry.kind.name,
            'name': entry.name,
            'content': entry.content,
            'certainty': entry.certainty.name,
            'data': entry.data,
            'provenance': entry.provenance,
            'atChapterId': entry.atChapterId,
          },
    ]);
  }

  /// Re-read every Markdown chapter. A body that differs from the current
  /// revision becomes a new revision (`reason: file`); a file without an id
  /// becomes a new chapter. Deleted files are left alone: deleting a chapter
  /// is too destructive to infer from a missing file.
  Future<int> importChanged() async {
    final books = Directory(p.join(root.path, 'books'));
    if (!await books.exists()) return 0;
    var changed = 0;
    await for (final book in books.list()) {
      if (book is! Directory) continue;
      final novelFile = File(p.join(book.path, 'novel.json'));
      if (!await novelFile.exists()) continue;
      final novel = await _readJson(novelFile);
      final novelId = novel['id'];
      if (novelId is! String) continue;

      final branches = Directory(p.join(book.path, 'branches'));
      if (!await branches.exists()) continue;
      await for (final branchDir in branches.list()) {
        if (branchDir is! Directory) continue;
        final branchFile = File(p.join(branchDir.path, 'branch.json'));
        if (!await branchFile.exists()) continue;
        final branch = await _readJson(branchFile);
        final branchId = branch['id'];
        if (branchId is! String) continue;

        final StorySnapshot story;
        try {
          story = await repository.getStory(branchId);
        } on Object {
          continue;
        }
        final byId = {
          for (final chapter in story.chapters) chapter.id: chapter,
        };

        final chaptersDir = Directory(p.join(branchDir.path, 'chapters'));
        if (!await chaptersDir.exists()) continue;
        await for (final file in chaptersDir.list()) {
          if (file is! File || !file.path.endsWith('.md')) continue;
          final parsed = _parseChapter(await file.readAsString());
          final existing = parsed.id == null ? null : byId[parsed.id];
          if (existing != null) {
            final revision = await repository.getRevision(existing.revisionId);
            final fileTime = await file.lastModified();
            if (parsed.body != existing.content.text &&
                fileTime.isAfter(revision.createdAt)) {
              await repository.saveChapter(
                branchId: branchId,
                chapterId: existing.id,
                expectedRevisionId: existing.revisionId,
                content: ManuscriptContent.plainText(parsed.body),
                reason: 'file',
              );
              changed++;
            }
          } else if (parsed.id == null && parsed.body.trim().isNotEmpty) {
            final chapter = await repository.createChapter(
              branchId: branchId,
              name: parsed.title,
              content: ManuscriptContent.plainText(parsed.body),
            );
            // Write the header now, or the next scan would create it again.
            await file.writeAsString(
              _chapterFile(chapter, _chapterTitle(chapter)),
            );
            changed++;
          }
        }
      }
    }
    return changed;
  }

  static String _chapterTitle(Chapter chapter) =>
      chapterTitle(chapter.number, chapter.name, chapter.numerals);

  static String _chapterFile(Chapter chapter, String title) =>
      '<!-- sillydraft\n'
      'id: ${chapter.id}\n'
      'revision: ${chapter.revisionId}\n'
      'title: ${title.replaceAll('\n', ' ')}\n'
      '-->\n\n'
      '${chapter.content.text}';

  static _ParsedChapter _parseChapter(String text) {
    final match = RegExp(
      r'^<!-- sillydraft\n(.*?)\n-->\n?',
      dotAll: true,
    ).firstMatch(text);
    if (match == null) return _ParsedChapter(null, '', text);
    final meta = <String, String>{};
    for (final line in match.group(1)!.split('\n')) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      meta[line.substring(0, colon).trim()] = line.substring(colon + 1).trim();
    }
    return _ParsedChapter(
      meta['id'],
      meta['title'] ?? '',
      text.substring(match.end),
    );
  }

  static String _slug(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final clipped = cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
    return clipped.isEmpty ? 'untitled' : clipped;
  }

  static Future<void> _writeJson(String path, Object value) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
  }

  static Future<Map<String, dynamic>> _readJson(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map<String, dynamic> ? decoded : const {};
  }
}

final class _ParsedChapter {
  const _ParsedChapter(this.id, this.title, this.body);
  final String? id;
  final String title;
  final String body;
}
