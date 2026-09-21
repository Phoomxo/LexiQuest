import 'runtime/ari_preview_feature_registry.dart';
import 'runtime/registries/feature_registry.dart';
import 'main.dart' show MyApp;
import 'runtime/app_bootstrap.dart';
import 'runtime/app_dependencies.dart';
import 'features/ai_tutor/application/menu_action_registry.dart';
import 'features/ai_tutor/presentation/menu_action_binding.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;
import 'config/m3_theme.dart';
import 'data/local/app_database.dart';
import 'features/identity/data/drift_local_owner_repository.dart';
import 'features/ai_tutor/application/managed_tutor_runtime.dart';
import 'features/ai_tutor/data/local_login_bridge.dart';
import 'features/ai_tutor/presentation/managed_tutor_test_screen.dart';
import 'features/vocabulary/data/packaged_starter_access.dart';

/// Explicit debug entry using the full application and its feature gates.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || !const bool.fromEnvironment('ARI_LOCAL_TEST')) {
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('รุ่นทดสอบยังไม่เปิดใช้งาน'))),
      ),
    );
    return;
  }
  runApp(const AriTestApp());
}

Future<LocalLoginBridge?> _loadLocalBridge() async {
  final support = await getApplicationSupportDirectory();
  final config = File('${support.path}/ari-bridge.json');
  if (!await config.exists()) return null;
  if (await config.length() > 1024) throw StateError('Invalid pairing');
  final data = jsonDecode(await config.readAsString()) as Map<String, dynamic>;
  await config.delete();
  final token = data['token'];
  if (token is! String || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
    throw StateError('Invalid pairing');
  }
  return LocalLoginBridge(token: token);
}

class AriTestApp extends StatefulWidget {
  const AriTestApp({super.key, this.loadDependencies, this.loadBridge});
  final Future<AppDependencies> Function()? loadDependencies;
  final Future<LocalLoginBridge?> Function()? loadBridge;
  @override
  State<AriTestApp> createState() => _AriTestAppState();
}

class _AriTestAppState extends State<AriTestApp> {
  AppDatabase? _database;
  AppDependencies? _dependencies;
  MenuActionRegistry? _menus;
  MenuRouteObserver? _menuRoutes;
  final _navigator = GlobalKey<NavigatorState>();
  bool _showChat = false;
  bool _aiPreparing = false;
  String _aiMessage =
      'ส่วนช่วยเหลือ AI เป็นตัวเลือก แอปหลักใช้งานได้โดยไม่เชื่อมบัญชี';
  ManagedTutorRuntime? _runtime;
  LocalLoginBridge? _bridge;
  String _message = 'กำลังเตรียมรุ่นทดสอบ';
  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      final dependencies =
          await (widget.loadDependencies ??
              AppBootstrap.production(
                buildFeatureRegistry: const AriPreviewFeatureRegistry(
                  BuildFeatureRegistry.fieldDefaults(),
                ),
              ).initialize)();
      if (!mounted) {
        await dependencies.dispose();
        return;
      }
      final menus = MenuActionRegistry(
        currentOwner: () => _runtime?.identity.value?.ownerId,
      );
      _menus = menus;
      _menuRoutes = MenuRouteObserver(menus);
      menus.register(
        id: 'navigation/back',
        label: 'ย้อนกลับ',
        available: () => _navigator.currentState?.canPop() == true,
        invoke: () {
          _navigator.currentState?.maybePop();
        },
      );
      setState(() {
        _dependencies = dependencies;
        _database = dependencies.database;
      });
    } on Object {
      if (mounted) setState(() => _message = 'เตรียมข้อมูลแอปไม่สำเร็จ');
    }
  }

  Future<void> _prepareAi() async {
    if (_aiPreparing || _runtime != null) return;
    setState(() => _aiPreparing = true);
    LocalLoginBridge? bridge;
    try {
      bridge = await (widget.loadBridge ?? _loadLocalBridge)();
      if (!mounted) {
        bridge?.dispose();
        return;
      }
      if (bridge == null) {
        setState(
          () => _aiMessage =
              'ยังไม่ได้จับคู่ส่วนช่วยเหลือ AI — ใช้งานแอปหลักต่อได้ตามปกติ',
        );
        return;
      }
      final database = _database;
      if (database == null) throw StateError('Local database unavailable');
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: const Uuid().v4,
        nowUtc: () => DateTime.now().toUtc(),
      );
      await owners.getOrCreateActiveOwner();
      if (!mounted) {
        bridge.dispose();
        return;
      }
      final activeBridge = bridge;
      final runtime = ManagedTutorRuntime(
        database: database,
        transport: activeBridge,
        network: activeBridge.network,
        operationTimeout: const Duration(seconds: 110),
        clearSession: () async {
          // Controller cancels the active request; screen owns account cleanup
          // so the private browser login can return without losing its session.
        },
      );
      final menus = _menus!;
      runtime.identity.addListener(() {
        menus.invalidateSession(preserveContext: true);
        _menuRoutes?.refresh();
        if (mounted) setState(() {});
      });
      activeBridge.menuActions = menus;
      _bridge = activeBridge;
      setState(() {
        _runtime = runtime;
      });
    } on Object {
      bridge?.dispose();
      if (mounted) {
        setState(
          () => _aiMessage =
              'ส่วนช่วยเหลือ AI ยังไม่พร้อม — ใช้งานแอปหลักต่อได้ตามปกติ',
        );
      }
    } finally {
      if (mounted) setState(() => _aiPreparing = false);
    }
  }

  @override
  void dispose() {
    unawaited(_runtime?.dispose());
    unawaited(_dependencies?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_dependencies == null) {
      return MaterialApp(
        theme: M3Theme.lightTheme,
        home: Scaffold(
          appBar: AppBar(title: const Text('อารี · รุ่นทดสอบ')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_message),
            ),
          ),
        ),
      );
    }
    return MenuActionScope(
      registry: _menus!,
      child: MyApp(
        dependencies: _dependencies!,
        ownsDependencies: false,
        navigatorKey: _navigator,
        additionalNavigatorObservers: [_menuRoutes!],
        shellBuilder: (context, child) => Column(
          children: [
            Expanded(child: child),
            Material(
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      key: const ValueKey('ari-toggle-chat'),
                      onPressed: () {
                        setState(() => _showChat = !_showChat);
                        if (_showChat) unawaited(_prepareAi());
                      },
                      icon: Icon(
                        _showChat
                            ? Icons.expand_more
                            : Icons.chat_bubble_outline,
                      ),
                      label: Text(
                        _showChat
                            ? 'ย่อส่วนช่วยเหลือ AI'
                            : 'เปิดส่วนช่วยเหลือ AI',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Offstage(
              offstage: !_showChat,
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .44,
                child: _runtime == null
                    ? Material(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: _aiPreparing
                                ? const Text(
                                    'กำลังเตรียมส่วนช่วยเหลือ AI — ใช้งานแอปหลักต่อได้',
                                  )
                                : Text(_aiMessage),
                          ),
                        ),
                      )
                    : ManagedTutorTestScreen(
                        embedded: true,
                        host: _runtime!.host,
                        bridge: _bridge!,
                        loadWords: () async {
                          final owner = _runtime!.identity.value?.ownerId;
                          if (owner == null) return [];
                          final db = _database!;
                          final rows =
                              await (db.select(db.vocabularyWords)
                                    ..where(
                                      (w) =>
                                          PackagedStarterAccess.wordsFor(
                                            db,
                                            owner,
                                          ) &
                                          w.isDeleted.equals(false),
                                    )
                                    ..orderBy([
                                      (w) => OrderingTerm.asc(w.spelling),
                                    ])
                                    ..limit(50))
                                  .get();
                          if (_runtime!.identity.value?.ownerId != owner) {
                            return [];
                          }
                          return rows
                              .map(
                                (w) => <String, dynamic>{
                                  'id': w.id,
                                  'spelling': w.spelling,
                                  'meaning': w.meaning,
                                  'partOfSpeech': w.partOfSpeech,
                                  'revision': w.contentRevision,
                                },
                              )
                              .toList();
                        },
                        openLogin: (_) => const MethodChannel(
                          'com.lexiquest.app/ari-test',
                        ).invokeMethod<void>('openLogin'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
