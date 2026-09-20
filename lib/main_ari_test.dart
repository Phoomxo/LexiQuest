import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'config/m3_theme.dart';
import 'data/local/app_database.dart';
import 'features/identity/data/drift_local_owner_repository.dart';
import 'features/ai_tutor/application/managed_tutor_runtime.dart';
import 'features/ai_tutor/data/local_login_bridge.dart';
import 'features/ai_tutor/presentation/managed_tutor_test_screen.dart';
import 'navigation/app_routes.dart';

/// Separate explicitly enabled debug entry. No Firebase/cloud/research bootstrap.
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
      final database = AppDatabase.production();
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
        await database.close();
        return;
      }
      final runtime = ManagedTutorRuntime(
        database: database,
        transport: bridge,
        network: bridge.network,
        clearSession: () async {
          // Tutor transport is disabled. Login cleanup is explicitly owned by
          // the screen, including owner change and private browser handoff.
        },
      );
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
    unawaited(_database?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: M3Theme.lightTheme,
    navigatorObservers: [appRouteObserver],
    home: _runtime == null
        ? Scaffold(
            appBar: AppBar(title: const Text('อารี · รุ่นทดสอบ')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_message),
              ),
            ),
          )
        : ManagedTutorTestScreen(
            host: _runtime!.host,
            bridge: _bridge!,
            openLogin: (_) => const MethodChannel(
              'com.lexiquest.app/ari-test',
            ).invokeMethod<void>('openLogin'),
          ),
  );
}
