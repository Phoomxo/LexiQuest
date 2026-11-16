import 'dart:async';

import 'package:flutter/material.dart';

import '../features/media_practice/application/device_permission_access.dart';
import '../features/media_practice/domain/media_practice_contracts.dart';
import '../runtime/app_dependencies.dart';

class DevicePermissionCenterScreen extends StatefulWidget {
  const DevicePermissionCenterScreen({super.key, this.permissionAccess});

  final DevicePermissionAccess? permissionAccess;

  @override
  State<DevicePermissionCenterScreen> createState() =>
      _DevicePermissionCenterScreenState();
}

class _DevicePermissionCenterScreenState
    extends State<DevicePermissionCenterScreen>
    with WidgetsBindingObserver {
  DevicePermissionAccess? _permissionAccess;
  MediaPermissionState? _camera;
  MediaPermissionState? _microphone;
  int _accessGeneration = 0;
  int _statusGeneration = 0;
  bool _openingSettings = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _replacePermissionAccess(
      widget.permissionAccess ??
          AppDependenciesScope.maybeOf(context)?.devicePermissions,
    );
  }

  @override
  void didUpdateWidget(DevicePermissionCenterScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.permissionAccess, widget.permissionAccess)) {
      _replacePermissionAccess(
        widget.permissionAccess ??
            AppDependenciesScope.maybeOf(context)?.devicePermissions,
      );
    }
  }

  void _replacePermissionAccess(DevicePermissionAccess? access) {
    if (identical(_permissionAccess, access)) return;
    _permissionAccess = access;
    _camera = null;
    _microphone = null;
    _openingSettings = false;
    _feedback = null;
    final generation = ++_accessGeneration;
    _statusGeneration++;
    if (access == null) {
      _camera = MediaPermissionState.unavailable;
      _microphone = MediaPermissionState.unavailable;
      return;
    }
    _startRefresh(access, generation);
  }

  void _startRefresh(DevicePermissionAccess access, int accessGeneration) {
    final statusGeneration = ++_statusGeneration;
    unawaited(_refresh(access, accessGeneration, statusGeneration));
  }

  Future<void> _refresh(
    DevicePermissionAccess access,
    int accessGeneration,
    int statusGeneration,
  ) async {
    final states = await Future.wait([
      _readSafely(access.cameraStatus),
      _readSafely(access.microphoneStatus),
    ]);
    if (!_isCurrent(access, accessGeneration) ||
        statusGeneration != _statusGeneration) {
      return;
    }
    setState(() {
      _camera = states[0];
      _microphone = states[1];
    });
  }

  Future<MediaPermissionState> _readSafely(
    Future<MediaPermissionState> Function() read,
  ) async {
    try {
      return await read();
    } catch (_) {
      return MediaPermissionState.unavailable;
    }
  }

  bool _isCurrent(DevicePermissionAccess access, int generation) =>
      mounted &&
      generation == _accessGeneration &&
      identical(access, _permissionAccess);

  Future<void> _openSettings() async {
    final access = _permissionAccess;
    if (access == null || _openingSettings) return;
    final generation = _accessGeneration;
    setState(() {
      _openingSettings = true;
      _feedback = null;
    });
    bool opened;
    try {
      opened = await access.openAndroidSettings();
    } catch (_) {
      opened = false;
    }
    if (!_isCurrent(access, generation)) return;
    setState(() {
      _openingSettings = false;
      _feedback = opened
          ? 'เมื่อปรับสิทธิ์แล้ว ให้กลับมาที่ LexiQuest เพื่อตรวจสอบอีกครั้ง'
          : 'เปิดการตั้งค่า Android ไม่สำเร็จ โปรดลองอีกครั้ง';
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final access = _permissionAccess;
    if (access == null) return;
    _startRefresh(access, _accessGeneration);
  }

  @override
  void dispose() {
    _accessGeneration++;
    _statusGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showSettings =
        _camera == MediaPermissionState.permanentlyDenied ||
        _microphone == MediaPermissionState.permanentlyDenied;
    return Scaffold(
      appBar: AppBar(title: const Text('สิทธิ์กล้องและไมโครโฟน')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'หน้านี้ตรวจสอบสถานะเท่านั้น '
            'LexiQuest จะขอสิทธิ์เมื่อคุณเริ่มใช้กล้องหรือไมโครโฟน',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          _permissionCard(
            permission: 'camera',
            icon: Icons.camera_alt_outlined,
            title: 'กล้อง',
            state: _camera,
          ),
          _permissionCard(
            permission: 'microphone',
            icon: Icons.mic_none,
            title: 'ไมโครโฟน',
            state: _microphone,
          ),
          if (showSettings) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey<String>('permission-center-open-settings'),
              onPressed: _openingSettings ? null : _openSettings,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: _openingSettings
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: 'กำลังเปิดการตั้งค่า Android',
                      ),
                    )
                  : const Icon(Icons.settings_outlined),
              label: Text(
                _openingSettings
                    ? 'กำลังเปิดการตั้งค่า…'
                    : 'เปิดการตั้งค่า Android',
              ),
            ),
          ],
          if (_feedback case final feedback?) ...[
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(feedback)),
          ],
        ],
      ),
    );
  }

  Widget _permissionCard({
    required String permission,
    required IconData icon,
    required String title,
    required MediaPermissionState? state,
  }) {
    final status = state == null ? 'กำลังตรวจสอบ…' : _statusText(state);
    return Card(
      child: ListTile(
        minTileHeight: 72,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Semantics(
          key: ValueKey<String>('permission-center-$permission-status'),
          liveRegion: true,
          label: '$title $status',
          child: ExcludeSemantics(child: Text(status)),
        ),
      ),
    );
  }

  String _statusText(MediaPermissionState state) => switch (state) {
    MediaPermissionState.granted => 'อนุญาตแล้ว',
    MediaPermissionState.denied => 'ยังไม่อนุญาต',
    MediaPermissionState.permanentlyDenied => 'ปิดถาวรในระบบ',
    MediaPermissionState.restricted => 'ถูกจำกัดโดยอุปกรณ์',
    MediaPermissionState.unavailable => 'ตรวจสอบสถานะไม่ได้',
  };
}
