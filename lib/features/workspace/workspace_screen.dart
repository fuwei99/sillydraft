import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sillydraft_workspace/sillydraft_workspace.dart';

/// Minimal on-device console for the proot workspace. It exists so the APK
/// can be tested without a desktop: request all-files access, install the
/// rootfs once, then run commands inside the mount table.
class WorkspaceSection extends StatefulWidget {
  const WorkspaceSection({super.key});

  @override
  State<WorkspaceSection> createState() => _WorkspaceSectionState();
}

class _WorkspaceSectionState extends State<WorkspaceSection> {
  static const _channel = MethodChannel('sillydraft/workspace');
  static const _rootfsUrl =
      'https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/'
      'ubuntu-base-24.04.3-base-arm64.tar.gz';

  final _command = TextEditingController(text: 'ls -la /mnt/sillydraft');
  String _nativeLibraryDir = '';
  String _filesDir = '';
  String _cacheDir = '';
  String _documentsRoot = '';
  bool _hasAccess = false;
  bool _rootfsReady = false;
  bool _busy = false;
  double? _progress;
  String _status = '正在读取设备路径…';
  String _log = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _command.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!Platform.isAndroid) {
      setState(() => _status = '工作区只在 Android 上可用');
      return;
    }
    try {
      final nativeLibraryDir =
          await _channel.invokeMethod<String>('nativeLibraryDir') ?? '';
      final filesDir = await _channel.invokeMethod<String>('filesDir') ?? '';
      final cacheDir = await _channel.invokeMethod<String>('cacheDir') ?? '';
      final documentsRoot =
          await _channel.invokeMethod<String>('documentsRoot') ?? '';
      final hasAccess =
          await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
      final ready = await File('$filesDir/rootfs/bin/sh').exists();
      if (!mounted) return;
      setState(() {
        _nativeLibraryDir = nativeLibraryDir;
        _filesDir = filesDir;
        _cacheDir = cacheDir;
        _documentsRoot = documentsRoot;
        _hasAccess = hasAccess;
        _rootfsReady = ready;
        _status = ready
            ? 'rootfs 已就绪'
            : hasAccess
            ? '需要安装 rootfs（约 30 MB）'
            : '需要「所有文件访问」权限';
      });
    } catch (e) {
      if (mounted) setState(() => _status = '读取设备路径失败：$e');
    }
  }

  Future<void> _requestAccess() async {
    await _channel.invokeMethod<bool>('requestAllFilesAccess');
    if (mounted) {
      setState(() => _status = '授权后回到这里，点「刷新状态」');
    }
  }

  Future<void> _installRootfs() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _status = '正在下载 rootfs…';
      _log = '';
    });
    HttpClient? client;
    try {
      final root = Directory('$_filesDir/rootfs');
      if (await root.exists()) await root.delete(recursive: true);
      await root.create(recursive: true);

      client = HttpClient();
      final request = await client.getUrl(Uri.parse(_rootfsUrl));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw StateError('下载失败：HTTP ${response.statusCode}');
      }
      final total = response.contentLength;
      final archive = File('$_cacheDir/rootfs.tar.gz');
      final sink = archive.openWrite();
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (mounted && total > 0) {
          setState(() => _progress = received / total);
        }
      }
      await sink.close();
      client.close();
      client = null;

      if (mounted) setState(() => _status = '正在解压…');
      await _channel.invokeMethod<bool>('extractRootfs', {
        'archive': archive.path,
        'target': root.path,
      });
      await archive.delete();
      final ready = await File('$_filesDir/rootfs/bin/sh').exists();
      if (!mounted) return;
      setState(() {
        _rootfsReady = ready;
        _status = ready ? 'rootfs 已安装' : '解压完成，但找不到 /bin/sh';
      });
    } catch (e) {
      if (mounted) setState(() => _status = '安装失败：$e');
    } finally {
      client?.close();
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _run() async {
    if (_busy) return;
    if (!_rootfsReady) {
      setState(() => _status = '先安装 rootfs');
      return;
    }
    setState(() {
      _busy = true;
      _log = '';
      _status = '运行中…';
    });
    try {
      final table = MountTable.standard(
        workspaceHost: '$_filesDir/workspace',
        dataHost: _documentsRoot,
      );
      await Directory('$_filesDir/workspace').create(recursive: true);
      final builder = ProotCommandBuilder(
        rootfsDir: '$_filesDir/rootfs',
        prootExecutable: '$_nativeLibraryDir/libproot_exec.so',
        loaderPath: '$_nativeLibraryDir/libproot_loader.so',
        tempDir: _cacheDir,
        hostWorkingDirectory: _filesDir,
      );
      final command = builder.build(
        table: table,
        command: _command.text,
        cwd: '/workspace',
      );
      final process = await Process.start(
        command.executable,
        command.args,
        environment: command.environment,
        workingDirectory: command.workingDirectory,
      );
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      final out = await stdoutFuture;
      final err = await stderrFuture;
      if (!mounted) return;
      setState(() {
        _log = [
          if (out.isNotEmpty) out,
          if (err.isNotEmpty) '--- stderr ---\n$err',
          '--- exit $exitCode ---',
        ].join('\n');
        _status = exitCode == 0 ? '完成' : '退出码 $exitCode';
      });
    } catch (e) {
      if (mounted) setState(() => _status = '运行失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final table = _filesDir.isEmpty || _documentsRoot.isEmpty
        ? null
        : MountTable.standard(
            workspaceHost: '$_filesDir/workspace',
            dataHost: _documentsRoot,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Agent 工作区',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Android 上的 proot Linux 工作区。默认只挂载 /workspace 和 '
          '/mnt/sillydraft，设备上的其他目录在 rootfs 里不存在。',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _busy ? null : _requestAccess,
              child: Text(_hasAccess ? '重新授权' : '申请所有文件访问'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _load,
              child: const Text('刷新状态'),
            ),
            OutlinedButton(
              onPressed: _busy || !_hasAccess ? null : _installRootfs,
              child: Text(_rootfsReady ? '重装 rootfs' : '安装 rootfs'),
            ),
          ],
        ),
        if (_progress != null) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _progress),
        ],
        const SizedBox(height: 12),
        Text(_status, style: theme.textTheme.bodySmall),
        const SizedBox(height: 20),
        TextField(
          controller: _command,
          minLines: 2,
          maxLines: 4,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(
            labelText: '命令',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _busy ? null : _run, child: const Text('运行')),
        if (_log.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              _log,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
        if (table != null) ...[
          const SizedBox(height: 24),
          Text('挂载表', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final entry in table.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${entry.guestPath}  ←  ${entry.hostPath}'
                '  (${entry.writable ? 'rw' : 'ro'})',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          const SizedBox(height: 16),
          Text('提示词', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SelectableText(
            buildWorkspacePrompt(table),
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ],
    );
  }
}
