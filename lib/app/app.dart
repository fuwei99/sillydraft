import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:sillydraft_core/sillydraft_core.dart';

import '../features/bookshelf/novel_start.dart';
import '../features/bookshelf/search_screen.dart';
import '../features/remote/library_switcher.dart';
import '../features/settings/settings_screen.dart';
import '../features/resources/resource_library_screen.dart';
import '../features/update/update_prompt.dart';
import 'desktop_commands.dart';
import 'devtool_trim.dart';
import 'home_screen.dart';
import 'library_host.dart';
import 'screen_awake.dart';
import 'services.dart';
import 'task_activity.dart';
import 'theme.dart';
import 'tracking.dart';
import 'widgets.dart' show AppDialog, confirmAction, showAppDialog, showError;

class SillyDraftApp extends StatefulWidget {
  const SillyDraftApp({super.key, required this.services, this.openLocal});
  final AppServices services;

  /// Reopens this device's library after a desktop's; tests pass their own.
  final Future<AppServices> Function()? openLocal;

  @override
  State<SillyDraftApp> createState() => _SillyDraftAppState();
}

class _SillyDraftAppState extends State<SillyDraftApp> {
  late final _host = LibraryHost(widget.services, openLocal: widget.openLocal);
  // Keep wake ownership across library switches, whose provider scopes reset.
  final _awake = ScreenAwake();

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _host,
    // A new scope per library: every provider and screen starts over.
    builder: (context, _) => ProviderScope(
      key: ObjectKey(_host.services),
      observers: [if (kDebugMode) DevtoolHistoryTrim()],
      overrides: [
        servicesProvider.overrideWithValue(_host.services),
        libraryHostProvider.overrideWithValue(_host),
        screenAwakeProvider.overrideWithValue(_awake),
      ],
      child: _App(showModelSetup: identical(_host.services, widget.services)),
    ),
  );
}

class _App extends ConsumerStatefulWidget {
  const _App({required this.showModelSetup});
  final bool showModelSetup;
  @override
  ConsumerState<_App> createState() => _AppState();
}

class _AppState extends ConsumerState<_App> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  final _tracking = ApplicationRouteObserver();
  late final ScreenAwake _awake;
  Future<AppExitResponse>? _exitRequest;
  int _selectedDestination = 0;

  void _selectDestination(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selectedDestination = index);
    _tracking.setHomeTab(index);
  }

  void _error(Object error) {
    final context = _navigator.currentContext;
    if (context != null) showError(context, '保存未完成：$error');
  }

  @override
  Future<AppExitResponse> didRequestAppExit() =>
      _exitRequest ??= _confirmExit().whenComplete(() => _exitRequest = null);

  Future<AppExitResponse> _confirmExit() async {
    try {
      final tasks = await ref
          .read(repositoryProvider)
          .listTasks(activeOnly: true);
      if (!mounted) return AppExitResponse.cancel;
      if (tasks.isNotEmpty) {
        final context = _navigator.currentState?.overlay?.context;
        if (context == null ||
            !context.mounted ||
            !await confirmAction(
              context,
              title: '仍有任务进行中',
              message: '还有 ${tasks.length} 个任务尚未完成。退出可能中断任务，建议保持应用打开并等待完成。',
              confirmLabel: '仍然退出',
              cancelLabel: '继续等待',
              destructive: true,
            )) {
          return AppExitResponse.cancel;
        }
      }
      if (!mounted) return AppExitResponse.cancel;
      await ref.read(servicesProvider).flushDrafts();
      unawaited(ApplicationTracking.current?.flush());
      return AppExitResponse.exit;
    } catch (e) {
      _error(e);
      return AppExitResponse.cancel;
    }
  }

  Future<void> _command(AppCommand command) async {
    final navigator = _navigator.currentState;
    if (navigator == null) return;
    try {
      if (command == AppCommand.save) {
        await ref.read(servicesProvider).flushDrafts();
      } else if (command == AppCommand.create) {
        await showNovelStart(navigator.context);
      } else if (!navigator.canPop() &&
          (command == AppCommand.resources || command == AppCommand.settings)) {
        _selectDestination(
          command == AppCommand.resources
              ? HomeTab.resources
              : HomeTab.settings,
        );
      } else {
        final screen = switch (command) {
          AppCommand.search => const GlobalSearchScreen(),
          AppCommand.resources => const ResourceLibraryScreen(),
          _ => const SettingsScreen(),
        };
        await navigator.push(
          MaterialPageRoute<void>(
            settings: RouteSettings(
              name: switch (command) {
                AppCommand.search => null,
                AppCommand.resources => '/resources',
                _ => '/settings',
              },
            ),
            builder: (_) => screen,
          ),
        );
      }
    } catch (e) {
      if (mounted) _error(e);
    }
  }

  @override
  void initState() {
    super.initState();
    _awake = ref.read(screenAwakeProvider);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startupPrompts());
    });
  }

  Future<void> _startupPrompts() async {
    final navigator = _navigator.currentState;
    if (navigator == null) return;
    final services = ref.read(servicesProvider);
    // Library switches rebuild this state; setup belongs to the initial launch.
    if (widget.showModelSetup && services.remote == null) {
      try {
        final connections = await services.connections();
        if (!mounted || !navigator.mounted) return;
        if (connections.isEmpty && !navigator.canPop()) {
          final configure = await showAppDialog<bool>(
            context: navigator.context,
            builder: (context) => AppDialog(
              key: const Key('model-setup-dialog'),
              title: const Text('连接模型，开始 AI 创作'),
              body: const Text(
                '还没有配置模型。只需两步，就能使用 AI 写作和编辑：\n\n'
                '1. 在「模型」设置中添加连接，填写模型服务的信息。\n'
                '2. 为写作、编辑等任务选择要使用的模型。\n\n'
                '也可以先离线使用，随时新建、编辑和阅读作品。',
              ),
              actions: [
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => Navigator.pop(context, false),
                  child: const Text('先离线使用'),
                ),
                FButton(
                  onPress: () => Navigator.pop(context, true),
                  child: const Text('去配置'),
                ),
              ],
            ),
          );
          if (!mounted || !navigator.mounted) return;
          if (configure == true) {
            await navigator.push<void>(
              MaterialPageRoute(
                settings: const RouteSettings(name: '/settings'),
                builder: (_) =>
                    const SettingsScreen(initialTab: SettingsTab.models),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted && navigator.mounted) {
          showError(navigator.context, '读取模型配置失败：$e');
        }
      }
    }
    if (mounted && navigator.mounted && !navigator.canPop()) {
      await checkUpdates(navigator.context, ref);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_awake.set(this, false));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(ApplicationTracking.current?.flush());
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_awake.refresh());
      final workspace = ref.read(servicesProvider).workspace;
      if (workspace != null) unawaited(workspace.syncFromFiles());
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(
        ref.read(servicesProvider).flushDrafts().catchError((Object e) {
          if (mounted) _error(e);
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeTasksProvider, (_, next) {
      unawaited(_awake.set(this, next.value?.isNotEmpty ?? false));
    });
    final mode = ref.watch(settingProvider('appearance')).value?['mode'];
    return MaterialApp(
      navigatorKey: _navigator,
      navigatorObservers: [_tracking],
      builder: (context, child) => mui.Theme(
        data: materialUiTheme(Theme.brightnessOf(context)),
        child: FTheme(
          data: appTheme(Theme.brightnessOf(context)),
          child: FToaster(
            child: FTooltipGroup(
              child: Overlay.wrap(
                child: RemoteFrame(
                  navigator: _navigator,
                  child: DesktopCommands(invoke: _command, child: child!),
                ),
              ),
            ),
          ),
        ),
      ),
      title: kDebugMode && defaultTargetPlatform == TargetPlatform.macOS
          ? 'SillyDraft Debug'
          : 'SillyDraft',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      // The SDK Material delegates serve the editor and routes; forui's list
      // adds its own strings plus package:material_ui's.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
        ...FLocalizations.localizationsDelegates,
      ],
      theme: sdkMaterialTheme(Brightness.light),
      darkTheme: sdkMaterialTheme(Brightness.dark),
      themeMode: mode == 'dark'
          ? ThemeMode.dark
          : mode == 'light'
          ? ThemeMode.light
          : ThemeMode.system,
      home: HomeScreen(
        selectedIndex: _selectedDestination,
        onDestinationSelected: _selectDestination,
        onExitRequested: () async {
          if (await didRequestAppExit() == AppExitResponse.exit) {
            await SystemNavigator.pop();
          }
        },
      ),
    );
  }
}
