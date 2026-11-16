import 'package:flutter/material.dart';

import '../config/app_appearance_preferences.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key, this.controller});

  final AppAppearanceController? controller;

  @override
  State<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  AppAppearanceController? _controller;
  AppAppearanceMode? _selected;
  bool _saving = false;
  String? _feedback;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= widget.controller ?? AppAppearanceScope.maybeOf(context);
    _selected ??= _controller?.mode ?? AppAppearanceMode.system;
  }

  Future<void> _save() async {
    final controller = _controller;
    final selected = _selected;
    if (_saving || controller == null || selected == null) return;
    setState(() {
      _saving = true;
      _feedback = null;
    });
    final saved = await controller.apply(selected);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _feedback = saved
          ? 'บันทึกการแสดงผลแล้ว'
          : 'บันทึกการแสดงผลไม่สำเร็จ กรุณาลองใหม่';
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected ?? AppAppearanceMode.system;
    return Scaffold(
      appBar: AppBar(title: const Text('การแสดงผล')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('โหมดสีของแอป', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          RadioGroup<AppAppearanceMode>(
            groupValue: selected,
            onChanged: (mode) {
              if (_saving || mode == null) return;
              setState(() {
                _selected = mode;
                _feedback = null;
              });
            },
            child: Column(
              children: [
                RadioListTile<AppAppearanceMode>(
                  value: AppAppearanceMode.system,
                  enabled: !_saving,
                  minTileHeight: 64,
                  title: const Text('ใช้ตามอุปกรณ์'),
                  subtitle: const Text('เปลี่ยนตามโหมดสว่างหรือมืดของอุปกรณ์'),
                ),
                RadioListTile<AppAppearanceMode>(
                  value: AppAppearanceMode.light,
                  enabled: !_saving,
                  minTileHeight: 64,
                  title: const Text('โหมดสว่าง'),
                ),
                RadioListTile<AppAppearanceMode>(
                  value: AppAppearanceMode.dark,
                  enabled: !_saving,
                  minTileHeight: 64,
                  title: const Text('โหมดมืด'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              key: const ValueKey<String>('appearance-save'),
              onPressed: _saving || _controller == null ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: 'กำลังบันทึกการแสดงผล',
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'กำลังบันทึก…' : 'บันทึกการแสดงผล'),
            ),
          ),
          if (_feedback case final feedback?) ...[
            const SizedBox(height: 16),
            Semantics(liveRegion: true, child: Text(feedback)),
          ],
        ],
      ),
    );
  }
}
