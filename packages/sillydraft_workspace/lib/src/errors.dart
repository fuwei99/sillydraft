/// Errors a tool call can surface to the model. Each message is written so a
/// model can act on it without guessing.
sealed class WorkspaceException implements Exception {
  const WorkspaceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The path is absolute and well formed, but no mount covers it.
final class OutsideWorkspaceException extends WorkspaceException {
  OutsideWorkspaceException(String path)
    : super('路径不在任何挂载点内：$path。可用的挂载点见 /workspace 和 /mnt/。');
}

/// A read-only mount was asked to change.
final class ReadOnlyMountException extends WorkspaceException {
  ReadOnlyMountException(String path, String mount)
    : super('$mount 是只读挂载，不能写入：$path');
}

final class GuestFileNotFound extends WorkspaceException {
  GuestFileNotFound(String path) : super('文件不存在：$path');
}

final class GuestFileTooLarge extends WorkspaceException {
  GuestFileTooLarge(String path, int bytes, int limit)
    : super('文件太大：$path（$bytes 字节，上限 $limit）');
}

final class NotTextFile extends WorkspaceException {
  NotTextFile(String path) : super('不是可解码的 UTF-8 文本：$path');
}

/// The file changed since the caller read it. Carries both hashes so the
/// caller can show a diff instead of silently overwriting the user's edit.
final class ContentConflict extends WorkspaceException {
  ContentConflict({
    required this.path,
    required this.expected,
    required this.actual,
  }) : super('文件已被改动，拒绝覆盖：$path（期望 $expected，实际 $actual）');

  final String path;
  final String? expected;
  final String? actual;
}

final class EditTargetNotFound extends WorkspaceException {
  EditTargetNotFound(String path) : super('要替换的文本在文件中不存在：$path');
}

final class AmbiguousEdit extends WorkspaceException {
  AmbiguousEdit(String path, int count)
    : super('要替换的文本在文件中出现了 $count 次，无法确定改哪一处：$path。请给更长的上下文。');
}
