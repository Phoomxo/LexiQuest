import 'dart:convert';
import '../features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:flutter/material.dart';

import '../features/learning_packs/domain/content_manifest.dart';
import '../features/offline_content/application/offline_content_manager.dart';
import '../features/offline_content/domain/offline_content_state.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/registries/feature_registry.dart';

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
  Future<List<_OfflineContentEntry>>? _states;
  final Set<ContentIdentity> _busy = <ContentIdentity>{};
  final Set<ContentIdentity> _downloads = <ContentIdentity>{};
  final Set<ContentIdentity> _cancelling = <ContentIdentity>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _states ??= _load();
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
    Future<T> Function() operation, {
    bool download = false,
  }) async {
    if (_busy.contains(identity) || !widget.canInvoke()) return;
    setState(() {
      _busy.add(identity);
      if (download) _downloads.add(identity);
    });
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
          _downloads.remove(identity);
          _states = _load();
        });
      }
    }
  }

  Future<void> _cancel(ContentIdentity identity) async {
    final manager = widget.manager;
    if (!widget.canInvoke() ||
        manager is! OfflineContentDownloadControl ||
        _cancelling.contains(identity)) {
      return;
    }
    setState(() => _cancelling.add(identity));
    try {
      final cancelled = await (manager as OfflineContentDownloadControl)
          .cancelDownload(identity);
      if (!cancelled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่มีการดาวน์โหลดที่ยกเลิกได้แล้ว')),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ยกเลิกไม่สำเร็จ ลองใหม่ได้')),
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling.remove(identity));
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
              return MenuActionBinding(
                id: 'offline/content/$index',
                label: 'Offline content item ${index + 1}',
                onInvoke: null,
                readValue: jsonEncode({
                  'type': identity.type.name,
                  'revision': identity.revision,
                  'title': String.fromCharCodes(entry.title.runes.take(80)),
                  'titleTruncated': entry.title.runes.length > 80,
                  'status': state.status.name,
                  'verified': state.hasVerifiedBytes,
                  'downloadedBytes': state.downloadedBytes,
                  'manifestBytes': entry.requiredBytes,
                  'byteCountMeaning': state.hasVerifiedBytes
                      ? 'installed-total-including-adapter-files'
                      : 'downloaded-so-far-not-verified',
                  'byteCountsComparableAsProgress': false,
                  'failureCode': state.failureCode?.name,
                  'inUse': !entry.canRemove,
                  'busy': _busy.contains(identity),
                  'cancelling': _cancelling.contains(identity),
                  'nativeActionsEnabled': widget.canInvoke(),
                  'interpretation':
                      'downloaded-bytes-do-not-imply-verified-or-cloud-synced',
                }),
                child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            entry.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Text(_statusText(state)),
                          if (!state.hasVerifiedBytes &&
                              entry.requiredBytes != null)
                            Text(
                              'พื้นที่ไฟล์อย่างน้อย ${_byteLabel(entry.requiredBytes!)} '
                              '· อาจต้องใช้พื้นที่ชั่วคราวเพิ่ม',
                            ),
                          if (!entry.canRemove) ...[
                            const SizedBox(height: 12),
                            const Text('จำเป็นต่อการเรียนที่กำลังดำเนินอยู่'),
                          ],
                          const SizedBox(height: 12),
                          _action(entry),
                          const SizedBox(height: 12),
                          ExpansionTile(
                            key: ValueKey(
                              'offline-content/details/${identity.id}',
                            ),
                            tilePadding: EdgeInsets.zero,
                            title: const Text('รายละเอียดไฟล์'),
                            children: [
                              Text(
                                'รหัส: ${identity.id} · รุ่น ${identity.revision}',
                              ),
                              Text(
                                '${state.hasVerifiedBytes ? 'ขนาดที่ตรวจสอบแล้ว' : 'ข้อมูลที่ดาวน์โหลดได้'}: ${state.downloadedBytes} ไบต์',
                              ),
                              if (state.failureCode != null)
                                Text(
                                  'สาเหตุ: ${_failureText(state.failureCode!)}',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
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
    final dependencies = AppDependenciesScope.maybeOf(context);
    final planning =
        dependencies?.features.isVisible(Feature.studyPlanning) == true
        ? dependencies?.studyPlanning
        : null;
    final states = await widget.manager.catalog();
    return Future.wait(
      states.map((state) async {
        final canRemove =
            state.status != OfflineContentStatus.verified ||
            await widget.manager.canRemove(state.identity);
        String? title;
        if (state.identity.type == ContentType.learningPack &&
            planning != null) {
          try {
            final detail = await planning.loadPinnedVersion(state.identity);
            if (detail.summary.contentIdentity == state.identity) {
              title = detail.summary.title;
            }
          } on Object {
            // Metadata is optional; never guess a name from ID or another revision.
          }
        }
        return _OfflineContentEntry(
          state: state,
          canRemove: canRemove,
          title: title ?? _typeLabel(state.identity.type),
          requiredBytes: widget.manager is OfflineContentDownloadControl
              ? await (widget.manager as OfflineContentDownloadControl)
                    .requiredBytes(state.identity)
              : null,
        );
      }),
    );
  }

  Widget _action(_OfflineContentEntry entry) {
    final state = entry.state;
    final identity = state.identity;
    if (_busy.contains(identity) ||
        state.status == OfflineContentStatus.downloading) {
      final busy = FilledButton(
        key: ValueKey<String>('offline-content/busy/${identity.id}'),
        onPressed: null,
        child: const Text('กำลังดำเนินการ'),
      );
      return Column(
        children: [
          busy,
          if (widget.manager is OfflineContentDownloadControl &&
              (_downloads.contains(identity) ||
                  state.status == OfflineContentStatus.downloading))
            TextButton(
              key: ValueKey('offline-content/cancel/${identity.id}'),
              onPressed: _cancelling.contains(identity)
                  ? null
                  : () => _cancel(identity),
              child: Text(
                _cancelling.contains(identity)
                    ? 'กำลังยกเลิกหลังขั้นตอนปัจจุบัน'
                    : 'ยกเลิกการดาวน์โหลด',
              ),
            ),
        ],
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
            : const ExcludeSemantics(child: Icon(Icons.lock_outline)),
      OfflineContentStatus.quarantined ||
      OfflineContentStatus.interrupted => FilledButton(
        key: ValueKey<String>('offline-content/repair/${identity.id}'),
        onPressed: () => _perform(
          identity,
          () async => widget.manager.repair(identity),
          download: true,
        ),
        child: const Text('ตรวจสอบและซ่อมไฟล์'),
      ),
      OfflineContentStatus.notDownloaded => FilledButton(
        key: ValueKey<String>('offline-content/download/${identity.id}'),
        onPressed: () => _perform(
          identity,
          () async => widget.manager.download(identity),
          download: true,
        ),
        child: const Text('ดาวน์โหลด'),
      ),
      OfflineContentStatus.downloading => const SizedBox.shrink(),
    };
  }

  String _statusText(OfflineContentState state) => switch (state.status) {
    OfflineContentStatus.notDownloaded => 'ยังไม่ได้ดาวน์โหลด',
    OfflineContentStatus.downloading => 'กำลังดาวน์โหลด',
    OfflineContentStatus.verified =>
      'พร้อมใช้งานออฟไลน์ · ${_byteLabel(state.downloadedBytes)}',
    OfflineContentStatus.interrupted => 'การดาวน์โหลดถูกขัดจังหวะ',
    OfflineContentStatus.quarantined => 'ไฟล์ไม่ผ่านการตรวจสอบและถูกกักไว้',
  };

  static String _typeLabel(ContentType type) => switch (type) {
    ContentType.learningPack => 'ชุดเนื้อหาการเรียน',
    ContentType.lexicalMetadata => 'ข้อมูลประกอบคำศัพท์',
    ContentType.assessmentForm => 'เนื้อหาแบบประเมิน',
    ContentType.offlineArtifact => 'ไฟล์สำหรับใช้งานออฟไลน์',
  };

  static String _byteLabel(int bytes) {
    if (bytes < 1024) return '$bytes ไบต์';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _failureText(OfflineContentFailureCode code) => switch (code) {
    OfflineContentFailureCode.checksumMismatch =>
      'เนื้อหาไฟล์ไม่ตรงกับฉบับที่ตรวจสอบ',
    OfflineContentFailureCode.sizeMismatch => 'ขนาดไฟล์ไม่ครบหรือไม่ตรง',
    OfflineContentFailureCode.revisionMismatch => 'ไฟล์คนละรุ่นกับที่ต้องใช้',
    OfflineContentFailureCode.missingArtifact => 'ไม่พบไฟล์ที่ต้องใช้',
    OfflineContentFailureCode.unsupportedContent => 'ยังไม่รองรับเนื้อหานี้',
    OfflineContentFailureCode.contentInUse => 'มีการเรียนที่ยังต้องใช้ไฟล์นี้',
    OfflineContentFailureCode.interrupted => 'การดาวน์โหลดถูกขัดจังหวะ',
    OfflineContentFailureCode.invalidState => 'สถานะไฟล์ไม่พร้อมใช้งาน',
  };
}

final class _OfflineContentEntry {
  const _OfflineContentEntry({
    required this.state,
    required this.canRemove,
    required this.title,
    this.requiredBytes,
  });

  final OfflineContentState state;
  final bool canRemove;
  final String title;
  final int? requiredBytes;
}
