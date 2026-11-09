/// The device-local Linux workspace, when one is installed and reachable.
///
/// The core package does not know how the workspace is mounted; the app
/// supplies an implementation backed by PRoot and the mount table. When
/// [available] is false the editor behaves exactly as before.
abstract interface class WorkspaceToolbox {
  /// True when the rootfs is installed and the library mount is reachable.
  bool get available;

  /// The `<workspace>` block appended to the editor's system prompt.
  String get prompt;

  /// OpenAI-style function schemas for read/write/edit/shell.
  List<Map<String, dynamic>> get tools;

  /// Whether [name] belongs to the workspace rather than the novel tools.
  bool handles(String name);

  /// Run a workspace tool and return its JSON result.
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> args);

  /// Write the current library to the public files, so the model and the
  /// author can read and edit it.
  Future<void> syncToFiles();

  /// Import Markdown chapters changed outside the app as new revisions.
  Future<void> syncFromFiles();
}
