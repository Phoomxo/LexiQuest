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
  runApp(const _AriTestApp());
}

class _AriTestApp extends StatefulWidget {
  const _AriTestApp();
  @override
  State<_AriTestApp> createState() => _AriTestAppState();
}

class _AriTestAppState extends State<_AriTestApp> {
  AppDatabase? _database;
  AppDependencies? _dependencies;
  MenuActionRegistry? _menus;
  MenuRouteObserver? _menuRoutes;
  final _navigator = GlobalKey<NavigatorState>();
  bool _showChat = true;
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
      final support = await getApplicationSupportDirectory();
      final config = File('${support.path}/ari-bridge.json');
      if (!await config.exists()) {
        if (mounted) {
          setState(() {
            _message =
                'พร้อมทดสอบหน้าจอ — ยังไม่ได้จับคู่สะพาน USB\nให้ผู้พัฒนาเตรียมสะพานทดสอบ แล้วเปิดแอปอีกครั้ง';
          });
        }
        return;
      }
      if (await config.length() > 1024) throw StateError('Invalid pairing');
      final data =
          jsonDecode(await config.readAsString()) as Map<String, dynamic>;
      await config.delete(); // Capability is memory-only after first read.
      final token = data['token'];
      if (token is! String || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
        throw StateError('Invalid pairing');
      }
      final bridge = LocalLoginBridge(token: token);
      final dependencies = await AppBootstrap.production().initialize();
      _dependencies = dependencies;
      final database = dependencies.database;
      if (database == null) throw StateError('Local database unavailable');
      _database = database;
      _bridge = bridge;
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: const Uuid().v4,
        nowUtc: () => DateTime.now().toUtc(),
      );
      await owners.getOrCreateActiveOwner();
      if (!mounted) {
        bridge.dispose();
        await dependencies.dispose();
        return;
      }
      final runtime = ManagedTutorRuntime(
        database: database,
        transport: bridge,
        network: bridge.network,
        operationTimeout: const Duration(seconds: 110),
        clearSession: () async {
          // Controller cancels the active request; screen owns account cleanup
          // so the private browser login can return without losing its session.
        },
      );
      final menus = MenuActionRegistry(
        currentOwner: () => runtime.identity.value?.ownerId,
      );
      runtime.identity.addListener(() {
        menus.invalidateSession();
        _menuRoutes?.refresh();
        if (mounted) setState(() {});
      });
      menus.register(
        id: 'navigation/back',
        label: 'ย้อนกลับ',
        available: () => _navigator.currentState?.canPop() == true,
        invoke: () {
          _navigator.currentState?.maybePop();
        },
      );
      bridge.menuActions = menus;
      _menus = menus;
      _menuRoutes = MenuRouteObserver(menus);
      setState(() {
        _runtime = runtime;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _message = 'เตรียมรุ่นทดสอบไม่ได้ กรุณาตรวจการจับคู่ USB';
        });
      }
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
    if (_runtime == null) {
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
                      onPressed: () => setState(() => _showChat = !_showChat),
                      icon: Icon(
                        _showChat
                            ? Icons.expand_more
                            : Icons.chat_bubble_outline,
                      ),
                      label: Text(
                        _showChat ? 'ย่อห้องสนทนาอารี' : 'เปิดห้องสนทนาอารี',
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
                child: ManagedTutorTestScreen(
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
                                    PackagedStarterAccess.wordsFor(db, owner) &
                                    w.isDeleted.equals(false),
                              )
                              ..orderBy([(w) => OrderingTerm.asc(w.spelling)])
                              ..limit(50))
                            .get();
                    if (_runtime!.identity.value?.ownerId != owner) return [];
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
