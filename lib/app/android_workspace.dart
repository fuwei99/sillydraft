import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sillydraft_core/sillydraft_core.dart';
import 'package:sillydraft_workspace/sillydraft_workspace.dart';

/// The Android workspace: a PRoot rootfs plus the mount table, exposed to the
/// editor agent as four tools. Paths come from [MainActivity] over the
/// `sillydraft/workspace` channel.
final class AndroidWorkspace implements WorkspaceToolbox {
  AndroidWorkspace._({
    required this.nativeLibraryDir,
    required this.filesDir,
    required this.cacheDir,
    required this.documentsRoot,
  });

  static const _channel = MethodChannel('sillydraft/workspace');

  final String nativeLibraryDir;
  final String filesDir;
  final String cacheDir;
  final String documentsRoot;

  MountTable? _table;
  WorkspaceTools? _tools;

  /// Null on every non-Android platform, and on Android before the channel
  /// answers.
  static Future<AndroidWorkspace?> load() async {
    if (!Platform.isAndroid) return null;
    try {
      final nativeLibraryDir = await _channel.invokeMethod<String>(
        'nativeLibraryDir',
      );
      final filesDir = await _channel.invokeMethod<String>('filesDir');
      final cacheDir = await _channel.invokeMethod<String>('cacheDir');
      final documentsRoot = await _channel.invokeMethod<String>(
        'documentsRoot',
      );
      if (nativeLibraryDir == null ||
          filesDir == null ||
          cacheDir == null ||
          documentsRoot == null) {
        return null;
      }
      return AndroidWorkspace._(
        nativeLibraryDir: nativeLibraryDir,
        filesDir: filesDir,
        cacheDir: cacheDir,
        documentsRoot: documentsRoot,
      );
    } catch (_) {
      return null;
    }
  }

  MountTable get table {
    Directory('$filesDir/workspace').createSync(recursive: true);
    return _table ??= MountTable.standard(
      workspaceHost: '$filesDir/workspace',
      dataHost: documentsRoot,
    );
  }

  WorkspaceTools get _toolbox => _tools ??= WorkspaceTools(
    files: WorkspaceFiles(table),
    shell: ProotShellRunner(
      builder: ProotCommandBuilder(
        rootfsDir: '$filesDir/rootfs',
        prootExecutable: '$nativeLibraryDir/libproot_exec.so',
        loaderPath: '$nativeLibraryDir/libproot_loader.so',
        tempDir: cacheDir,
        hostWorkingDirectory: filesDir,
      ),
      table: table,
    ),
  );

  @override
  bool get available =>
      Platform.isAndroid &&
      File('$filesDir/rootfs/bin/sh').existsSync() &&
      Directory(documentsRoot).existsSync();

  @override
  String get prompt => available ? buildWorkspacePrompt(table) : '';

  @override
  List<Map<String, dynamic>> get tools =>
      available ? _toolbox.schemas(background: false) : const [];

  static const _names = {'read_file', 'write_file', 'edit_file', 'shell'};

  @override
  bool handles(String name) => _names.contains(name);

  @override
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> args,
  ) async {
    final result = await _toolbox.call(name, args);
    try {
      final decoded = jsonDecode(result.content);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Fall through: hand the model a readable error instead of throwing.
    }
    return {'error': result.content};
  }
}
