import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/media_practice/application/device_permission_access.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/device_permission_center_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

const _settingsKey = ValueKey<String>('permission-center-open-settings');

void main() {
  testWidgets('opening reads status only and never opens Android settings', (
    tester,
  ) async {
    final access = _PermissionAccess(
      camera: MediaPermissionState.granted,
      microphone: MediaPermissionState.denied,
    );
    await _pump(tester, access);

    expect(access.cameraReads, 1);
    expect(access.microphoneReads, 1);
    expect(access.settingsOpens, 0);
    expect(find.text('อนุญาตแล้ว'), findsOneWidget);
    expect(find.text('ยังไม่อนุญาต'), findsOneWidget);
    expect(find.byKey(_settingsKey), findsNothing);
  });

  testWidgets('shows all five permission states in plain Thai', (tester) async {
    for (final (state, text) in <(MediaPermissionState, String)>[
      (MediaPermissionState.granted, 'อนุญาตแล้ว'),
      (MediaPermissionState.denied, 'ยังไม่อนุญาต'),
      (MediaPermissionState.permanentlyDenied, 'ปิดถาวรในระบบ'),
      (MediaPermissionState.restricted, 'ถูกจำกัดโดยอุปกรณ์'),
      (MediaPermissionState.unavailable, 'ตรวจสอบสถานะไม่ได้'),
    ]) {
      await _pump(tester, _PermissionAccess(camera: state, microphone: state));
      expect(find.text(text), findsNWidgets(2), reason: state.name);
    }
  });

  testWidgets('status failures fail closed without exposing error details', (
    tester,
  ) async {
    final access = _PermissionAccess(
      camera: MediaPermissionState.granted,
      microphone: MediaPermissionState.granted,
      cameraError: StateError('private-camera-sentinel'),
      microphoneError: StateError('private-microphone-sentinel'),
    );
    await _pump(tester, access);

    expect(find.text('ตรวจสอบสถานะไม่ได้'), findsNWidgets(2));
    expect(find.textContaining('private-camera-sentinel'), findsNothing);
    expect(find.textContaining('private-microphone-sentinel'), findsNothing);
  });

  testWidgets('permanent denial opens settings only after explicit tap', (
    tester,
  ) async {
    final gate = Completer<bool>();
    final access = _PermissionAccess(
      camera: MediaPermissionState.permanentlyDenied,
      microphone: MediaPermissionState.denied,
      openResult: gate.future,
    );
    await _pump(tester, access);

    expect(access.settingsOpens, 0);
    await tester.tap(find.byKey(_settingsKey));
    await tester.pump();
    await tester.tap(find.byKey(_settingsKey));
    expect(access.settingsOpens, 1);
    expect(
      tester.widget<FilledButton>(find.byKey(_settingsKey)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .semanticsLabel,
      'กำลังเปิดการตั้งค่า Android',
    );

    gate.complete(true);
    await tester.pumpAndSettle();
    final feedback = find.textContaining('กลับมาที่ LexiQuest');
    expect(feedback, findsOneWidget);
    expect(
      tester
          .widgetList<Semantics>(
            find.ancestor(of: feedback, matching: find.byType(Semantics)),
          )
          .any((widget) => widget.properties.liveRegion == true),
      isTrue,
    );
  });

  testWidgets('resume refreshes both statuses without opening settings', (
    tester,
  ) async {
    final access = _PermissionAccess(
      camera: MediaPermissionState.denied,
      microphone: MediaPermissionState.denied,
    );
    await _pump(tester, access);
    access
      ..camera = MediaPermissionState.granted
      ..microphone = MediaPermissionState.granted;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(access.cameraReads, 2);
    expect(access.microphoneReads, 2);
    expect(access.settingsOpens, 0);
    expect(find.text('อนุญาตแล้ว'), findsNWidgets(2));
    expect(_statusSemantics(tester, 'camera').properties.liveRegion, isTrue);
    expect(
      _statusSemantics(tester, 'camera').properties.label,
      'กล้อง อนุญาตแล้ว',
    );
    expect(
      _statusSemantics(tester, 'microphone').properties.liveRegion,
      isTrue,
    );
    expect(
      _statusSemantics(tester, 'microphone').properties.label,
      'ไมโครโฟน อนุญาตแล้ว',
    );
  });

  testWidgets('late old status cannot replace a newer injected access', (
    tester,
  ) async {
    final oldCamera = Completer<MediaPermissionState>();
    final oldMicrophone = Completer<MediaPermissionState>();
    final oldAccess = _PermissionAccess(
      camera: MediaPermissionState.denied,
      microphone: MediaPermissionState.denied,
      cameraResult: oldCamera.future,
      microphoneResult: oldMicrophone.future,
    );
    final newAccess = _PermissionAccess(
      camera: MediaPermissionState.granted,
      microphone: MediaPermissionState.granted,
    );
    const key = ValueKey<String>('stable-permission-center');
    await _pump(tester, oldAccess, key: key, settle: false);
    await _pump(tester, newAccess, key: key);

    oldCamera.complete(MediaPermissionState.permanentlyDenied);
    oldMicrophone.complete(MediaPermissionState.permanentlyDenied);
    await tester.pumpAndSettle();

    expect(find.text('อนุญาตแล้ว'), findsNWidgets(2));
    expect(find.text('ปิดถาวรในระบบ'), findsNothing);
  });

  testWidgets('nonnull injection can fall back to a newer scope dependency', (
    tester,
  ) async {
    final injected = _PermissionAccess(
      camera: MediaPermissionState.permanentlyDenied,
      microphone: MediaPermissionState.permanentlyDenied,
    );
    final fallback = _PermissionAccess(
      camera: MediaPermissionState.granted,
      microphone: MediaPermissionState.granted,
    );
    const key = ValueKey<String>('scope-fallback-permission-center');
    await _pump(tester, injected, key: key, scopeAccess: fallback);
    expect(find.text('ปิดถาวรในระบบ'), findsNWidgets(2));
    expect(fallback.cameraReads, 0);

    await _pump(tester, null, key: key, scopeAccess: fallback);

    expect(fallback.cameraReads, 1);
    expect(fallback.microphoneReads, 1);
    expect(find.text('อนุญาตแล้ว'), findsNWidgets(2));
    expect(find.text('ปิดถาวรในระบบ'), findsNothing);
  });

  testWidgets('late initial read cannot replace a newer resume refresh', (
    tester,
  ) async {
    final access = _SequencedPermissionAccess();
    await _pump(tester, access, settle: false);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('อนุญาตแล้ว'), findsNWidgets(2));

    access.completeInitial(MediaPermissionState.permanentlyDenied);
    await tester.pumpAndSettle();
    expect(find.text('อนุญาตแล้ว'), findsNWidgets(2));
    expect(find.text('ปิดถาวรในระบบ'), findsNothing);
  });

  testWidgets('supports compact portrait and landscape at 200 percent text', (
    tester,
  ) async {
    for (final (size, mode) in <(Size, ThemeMode)>[
      (const Size(360, 800), ThemeMode.light),
      (const Size(800, 360), ThemeMode.dark),
    ]) {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      await _pump(
        tester,
        _PermissionAccess(
          camera: MediaPermissionState.permanentlyDenied,
          microphone: MediaPermissionState.permanentlyDenied,
        ),
        textScale: 2,
        themeMode: mode,
      );
      await tester.scrollUntilVisible(find.byKey(_settingsKey), 160);
      await tester.ensureVisible(find.byKey(_settingsKey));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(_settingsKey)).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull, reason: '$size $mode');
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}

Future<void> _pump(
  WidgetTester tester,
  DevicePermissionAccess? access, {
  DevicePermissionAccess? scopeAccess,
  Key? key,
  double textScale = 1,
  ThemeMode themeMode = ThemeMode.light,
  bool settle = true,
}) async {
  Widget app = MaterialApp(
    theme: M3Theme.lightTheme,
    darkTheme: M3Theme.darkTheme,
    themeMode: themeMode,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: DevicePermissionCenterScreen(
      key: key ?? UniqueKey(),
      permissionAccess: access,
    ),
  );
  if (scopeAccess != null) {
    app = AppDependenciesScope(
      dependencies: AppDependencies(
        runtimeStatus: const AppRuntimeStatus(
          localData: RuntimeAvailability.ready,
          firebase: RuntimeAvailability.ready,
          supabase: RuntimeAvailability.ready,
          backends: RuntimeAvailability.ready,
        ),
        config: null,
        guestSessionService: const _GuestSessionService(),
        devicePermissions: scopeAccess,
      ),
      child: app,
    );
  }
  await tester.pumpWidget(app);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Semantics _statusSemantics(WidgetTester tester, String permission) =>
    tester.widget<Semantics>(
      find.byKey(ValueKey<String>('permission-center-$permission-status')),
    );

final class _PermissionAccess implements DevicePermissionAccess {
  _PermissionAccess({
    required this.camera,
    required this.microphone,
    this.cameraError,
    this.microphoneError,
    this.cameraResult,
    this.microphoneResult,
    this.openResult,
  });

  MediaPermissionState camera;
  MediaPermissionState microphone;
  final Object? cameraError;
  final Object? microphoneError;
  final Future<MediaPermissionState>? cameraResult;
  final Future<MediaPermissionState>? microphoneResult;
  final Future<bool>? openResult;
  int cameraReads = 0;
  int microphoneReads = 0;
  int settingsOpens = 0;

  @override
  Future<MediaPermissionState> cameraStatus() async {
    cameraReads++;
    if (cameraError case final error?) throw error;
    return await cameraResult ?? camera;
  }

  @override
  Future<MediaPermissionState> microphoneStatus() async {
    microphoneReads++;
    if (microphoneError case final error?) throw error;
    return await microphoneResult ?? microphone;
  }

  @override
  Future<bool> openAndroidSettings() async {
    settingsOpens++;
    return await openResult ?? true;
  }
}

final class _SequencedPermissionAccess implements DevicePermissionAccess {
  final _firstCamera = Completer<MediaPermissionState>();
  final _firstMicrophone = Completer<MediaPermissionState>();
  int _cameraReads = 0;
  int _microphoneReads = 0;

  void completeInitial(MediaPermissionState state) {
    _firstCamera.complete(state);
    _firstMicrophone.complete(state);
  }

  @override
  Future<MediaPermissionState> cameraStatus() {
    _cameraReads++;
    return _cameraReads == 1
        ? _firstCamera.future
        : Future.value(MediaPermissionState.granted);
  }

  @override
  Future<MediaPermissionState> microphoneStatus() {
    _microphoneReads++;
    return _microphoneReads == 1
        ? _firstMicrophone.future
        : Future.value(MediaPermissionState.granted);
  }

  @override
  Future<bool> openAndroidSettings() async => true;
}

final class _GuestSessionService implements GuestSessionService {
  const _GuestSessionService();

  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'synthetic-guest');
}
