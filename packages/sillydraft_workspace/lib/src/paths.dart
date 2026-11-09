/// Guest-side paths. The agent only ever sees these; host paths never appear
/// in a prompt or a tool result.
abstract final class WorkspacePaths {
  /// The agent's own scratch area. Always mounted, always writable.
  static const String workspace = '/workspace';

  /// Every user-added mount lives below this.
  static const String mountRoot = '/mnt';

  /// The one mount a fresh install has: the user's SillyDraft library.
  static const String data = '/mnt/sillydraft';

  static const String dataLabel = 'sillydraft';
}
