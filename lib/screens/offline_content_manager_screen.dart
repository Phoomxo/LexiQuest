import 'package:flutter/material.dart';

import '../features/learning_packs/domain/content_manifest.dart';
import '../features/offline_content/application/offline_content_manager.dart';
import '../features/offline_content/domain/offline_content_state.dart';

final class OfflineContentManagerScreen extends StatefulWidget {
  const OfflineContentManagerScreen({
    super.key,
    required this.manager,
    required this.canInvoke,
  });

  final OfflineContentManager manager;
  final bool Function() canInvoke;

  @override
  State<OfflineContentManagerScreen> createState() =>
      _OfflineContentManagerScreenState();
}

final class _OfflineContentManagerScreenState
    extends State<OfflineContentManagerScreen> {
  late Future<List<_OfflineContentEntry>> _states;
  final Set<ContentIdentity> _busy = <ContentIdentity>{};

  @override
  void initState() {
    super.initState();
    _states = _load();
  }

  @override
  void didUpdateWidget(OfflineContentManagerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.manager, widget.manager)) {
      _states = _load();
    }
  }

  Future<void> _perform<T>(
    ContentIdentity identity,
    Future<T> Function() operation,
  ) async {
    if (_busy.contains(identity) || !widget.canInvoke()) return;
    setState(() => _busy.add(identity));
    try {
      await operation();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('จัดการเนื้อหาออฟไลน์ไม่สำเร็จ ลองใหม่ได้'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(identity);
          _states = _load();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เนื้อหาออฟไลน์')),
      body: FutureBuilder<List<_OfflineContentEntry>>(
        future: _states,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('อ่านสถานะเนื้อหาออฟไลน์ไม่ได้'),
              ),
            );
          }
          final states = snapshot.data ?? const <_OfflineContentEntry>[];
          if (states.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('ยังไม่มีแพ็กเนื้อหาที่รองรับการใช้งานออฟไลน์'),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: states.length,
            itemBuilder: (context, index) {
              final entry = states[index];
              final state = entry.state;
              final identity = state.identity;
              final semanticLabel =
                  '${identity.type.name} ${identity.id} '
                  'revision ${identity.revision}'
                  '${entry.canRemove ? '' : ' required by active learning'}';
              return Semantics(
                container: true,
                explicitChildNodes: true,
                label: semanticLabel,
                child: Card(
                  child: ListTile(
                    title: Text(identity.id),
                    subtitle: Text(_statusText(state)),
                    trailing: _action(entry),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<List<_OfflineContentEntry>> _load() async {
    final states = await widget.manager.catalog();
    return Future.wait(
      states.map((state) async {
        final canRemove =
            state.status != OfflineContentStatus.verified ||
            await widget.manager.canRemove(state.identity);
        return _OfflineContentEntry(state: state, canRemove: canRemove);
      }),
    );
  }

  Widget _action(_OfflineContentEntry entry) {
    final state = entry.state;
    final identity = state.identity;
    if (_busy.contains(identity) ||
        state.status == OfflineContentStatus.downloading) {
      return FilledButton(
        key: ValueKey<String>('offline-content/busy/${identity.id}'),
        onPressed: null,
        child: const Text('กำลังดำเนินการ'),
      );
    }
    return switch (state.status) {
      OfflineContentStatus.verified =>
        entry.canRemove
            ? OutlinedButton(
                key: ValueKey<String>('offline-content/remove/${identity.id}'),
                onPressed: () => _perform(
                  identity,
                  () => widget.manager.removeBytes(identity),
                ),
                child: const Text('ลบไฟล์'),
              )
            : Tooltip(
                message: 'จำเป็นต่อการเรียนที่กำลังดำเนินอยู่',
                excludeFromSemantics: true,
                child: Semantics(
                  container: true,
                  label: 'จำเป็นต่อการเรียนที่กำลังดำเนินอยู่',
                  excludeSemantics: true,
                  child: const Icon(Icons.lock_outline),
                ),
              ),
      OfflineContentStatus.quarantined ||
      OfflineContentStatus.interrupted => FilledButton(
        key: ValueKey<String>('offline-content/repair/${identity.id}'),
        onPressed: () =>
            _perform(identity, () async => widget.manager.repair(identity)),
        child: const Text('ซ่อมแซม'),
      ),
      OfflineContentStatus.notDownloaded => FilledButton(
        key: ValueKey<String>('offline-content/download/${identity.id}'),
        onPressed: () =>
            _perform(identity, () async => widget.manager.download(identity)),
        child: const Text('ดาวน์โหลด'),
      ),
      OfflineContentStatus.downloading => const SizedBox.shrink(),
    };
  }

  String _statusText(OfflineContentState state) => switch (state.status) {
    OfflineContentStatus.notDownloaded => 'ยังไม่ได้ดาวน์โหลด',
    OfflineContentStatus.downloading => 'กำลังดาวน์โหลด',
    OfflineContentStatus.verified =>
      'พร้อมใช้งานออฟไลน์ • ${state.downloadedBytes} ไบต์',
    OfflineContentStatus.interrupted => 'การดาวน์โหลดถูกขัดจังหวะ',
    OfflineContentStatus.quarantined => 'ไฟล์ไม่ผ่านการตรวจสอบและถูกกักไว้',
  };
}

final class _OfflineContentEntry {
  const _OfflineContentEntry({required this.state, required this.canRemove});

  final OfflineContentState state;
  final bool canRemove;
}
