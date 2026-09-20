import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import '../../../data/local/app_database.dart';
import '../../ai_tutor/domain/ai_tutor_contracts.dart';
import '../../identity/application/owner_generation.dart';
import '../../learning_packs/application/personal_sets_use_cases.dart';
import '../../learning_packs/domain/personal_sets.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../../sync/data/drift_owner_operation_gate.dart';
import '../../vocabulary/data/drift_vocabulary_repository.dart';
import '../../vocabulary/data/packaged_starter_access.dart';
import '../../learning/domain/context_practice.dart';
import '../domain/audio_lesson.dart';
import 'voice_use_cases.dart';
import '../../../voice/voice_models.dart';
import '../../../voice/voice_audio_cache.dart';
import '../../../voice/lesson_audio_cache.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

final class AudioLessonRollout {
  const AudioLessonRollout.implementedOff() : enabled = false;
  const AudioLessonRollout.internal() : enabled = true;
  final bool enabled;
}

final class AudioLessonTicket {
  AudioLessonTicket._(
    this.owner,
    this.set,
    this.format,
    this.activityId,
    this.completedSegments,
  ) : scripts = List.unmodifiable(
        set.members.map((r) => AudioLessonScript.forSense(r, format)),
      );
  final OwnerGenerationToken owner;
  final PersonalSetRevision set;
  final AudioLessonFormat format;
  final String activityId;
  final int completedSegments;
  final List<AudioLessonScript> scripts;
  bool _cancelled = false;
  List<String> get segments =>
      List.unmodifiable(scripts.expand((s) => s.segments));
  String get transcript => segments.join('\n\n');
  Map<String, Object?> get pin => {
    'schemaVersion': 1,
    'set': set.toJson(),
    'format': format.name,
    'scripts': scripts.map((s) => s.toJson()).toList(),
  };
  String get contentHash =>
      sha256.convert(utf8.encode(jsonEncode(pin))).toString();
  void cancel() => _cancelled = true;
  AudioLessonTicket _at(int completed) =>
      AudioLessonTicket._(owner, set, format, activityId, completed);
}

final class AudioLessonUseCases {
  AudioLessonUseCases({
    required this.sets,
    required this.voice,
    required this.isAvailable,
  });
  final PersonalSetsUseCases sets;
  final VoiceUseCases? voice;
  final bool Function() isAvailable;
  AppDatabase get database => sets.repository.database;
  final _players = <AudioLessonPlayback>{};
  OwnerGenerationToken? _cacheOwner;
  LessonAudioCache? _cache;
  StreamSubscription<bool>? _watch;
  bool _disposed = false;

  Future<void> _fence(
    OwnerGenerationToken owner, [
    AudioLessonTicket? ticket,
    bool available = true,
  ]) async {
    if (_disposed ||
        (available && !isAvailable()) ||
        (ticket?._cancelled ?? false)) {
      throw StateError('Audio lesson retired');
    }
    await sets.ownerGeneration.requireCurrentAsync(owner);
    await DriftOwnerOperationGate(database).requireOwned(
      token: sets.ownerOperations.currentOperationVersion,
      nowUtc: sets.repository.nowUtc(),
    );
    sets.ownerGeneration.requireCurrent(owner);
    if (_disposed ||
        (available && !isAvailable()) ||
        (ticket?._cancelled ?? false)) {
      throw StateError('Audio lesson retired');
    }
  }

  Future<T> _run<T>(
    OwnerGenerationToken owner,
    Future<T> Function() action, [
    AudioLessonTicket? ticket,
    bool available = true,
  ]) async {
    await sets.ownerGeneration.requireCurrentAsync(owner);
    return sets.ownerOperations.run(AiCancellation(), (active) async {
      if (active != owner.ownerId) throw StateError('Audio owner changed');
      return database.transaction(() async {
        await _fence(owner, ticket, available);
        final value = await action();
        await _fence(owner, ticket, available);
        return value;
      });
    });
  }

  Future<AudioLessonTicket> open(
    OwnerGenerationToken owner, {
    required String setId,
    required int setRevision,
    required String activityId,
    required AudioLessonFormat format,
  }) => _run(owner, () async {
    if (activityId.isEmpty ||
        activityId != activityId.trim() ||
        activityId.length > 200 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(activityId)) {
      throw ArgumentError('Invalid audio identity');
    }
    final set = await sets.repository.readExact(
      ownerId: owner.ownerId,
      setId: setId,
      revision: setRevision,
    );
    if (set == null ||
        set.archived ||
        set.members.isEmpty ||
        set.members.length > 100) {
      throw StateError('Audio set unavailable');
    }
    final ticket = AudioLessonTicket._(owner, set, format, activityId, 0);
    await _admit(ticket);
    final rows = await _rows(ticket);
    if (rows.isEmpty) await _insert(ticket, 0, null);
    return _load(ticket);
  });

  Future<void> _admit(AudioLessonTicket ticket) async {
    final current = await sets.repository.readExact(
      ownerId: ticket.owner.ownerId,
      setId: ticket.set.setId,
      revision: ticket.set.revision,
    );
    if (current?.payloadHash != ticket.set.payloadHash || current!.archived) {
      throw StateError('Set pin changed');
    }
    for (final ref in ticket.set.members) {
      final context = const ContextPracticeInventory().find(ref.wordId);
      if (context == null ||
          ref.senseKey != 'starter-object-v1' ||
          ref.senseRevision != 1 ||
          ref.lexicalArtifactHash != context.artifactHash) {
        throw StateError('Unreviewed audio sense');
      }
      final crosswalk = await sets.repository.crosswalks.requirePinned(
        ticket.set.crosswalkPin,
      );
      final entry = crosswalk.resolve(ref);
      final word = (await DriftVocabularyRepository(
        database,
        contentManifests: sets.repository.crosswalks.manifests,
      ).readPinnedByIds([ref.wordId])).single;
      final categories =
          await (database.select(database.vocabularyCategories)..where(
                (r) =>
                    PackagedStarterAccess.categoriesFor(
                      database,
                      ticket.owner.ownerId,
                    ) &
                    r.isDeleted.equals(false),
              ))
              .get();
      final artifact = await sets.repository.crosswalks.manifests
          .requireVerified(
            ContentIdentity(
              type: ContentType.lexicalMetadata,
              id: ref.wordId,
              revision: entry.wordRevision,
            ),
          );
      crosswalk.requireScored(
        ref,
        word: word,
        categoryAvailable: categories.any((c) => c.id == word.categoryId),
        lexicalArtifact: artifact,
      );
    }
  }

  Future<List<AudioLessonCheckpoint>> _rows(AudioLessonTicket t) =>
      (database.select(database.audioLessonCheckpoints)
            ..where(
              (r) =>
                  r.ownerId.equals(t.owner.ownerId) &
                  r.activityId.equals(t.activityId),
            )
            ..orderBy([(r) => OrderingTerm.asc(r.revision)]))
          .get();
  Future<AudioLessonTicket> _load(AudioLessonTicket t) async {
    final rows = await _rows(t);
    if (rows.isEmpty || rows.length > t.segments.length + 1) {
      throw StateError('Invalid audio history');
    }
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final payload = jsonDecode(row.payloadJson) as Map;
      if (row.revision != i + 1 ||
          row.operationId != _operation(t, i) ||
          payload.length != 3 ||
          payload['completedSegments'] != i ||
          jsonEncode(payload['pin']) != jsonEncode(t.pin) ||
          (i == 0
              ? payload['playback'] != null
              : !_validPlayback(payload['playback']))) {
        throw StateError('Audio checkpoint identity mismatch');
      }
    }
    return t._at(rows.length - 1);
  }

  bool _validPlayback(Object? value) =>
      value is Map &&
      value.length == 3 &&
      VoiceEngine.values.any((e) => e.name == value['engine']) &&
      (value['modelVersion'] == null || value['modelVersion'] is String) &&
      value['completion'] == 'exact-provider-segment';
  String _operation(AudioLessonTicket t, int count) =>
      'audio:${sha256.convert(utf8.encode('${t.activityId}:$count'))}';
  Future<void> _insert(
    AudioLessonTicket t,
    int completed,
    VoicePlaybackResult? result,
  ) => database
      .into(database.audioLessonCheckpoints)
      .insert(
        AudioLessonCheckpointsCompanion.insert(
          ownerId: t.owner.ownerId,
          activityId: t.activityId,
          revision: completed + 1,
          operationId: _operation(t, completed),
          payloadJson: jsonEncode({
            'pin': t.pin,
            'completedSegments': completed,
            'playback': result == null
                ? null
                : {
                    'engine': result.actualEngine.name,
                    'modelVersion': result.modelVersion,
                    'completion': 'exact-provider-segment',
                  },
          }),
        ),
      )
      .then((_) {});
  Future<void> validate(AudioLessonTicket t) =>
      _run(t.owner, () => _admit(t), t);
  Future<AudioLessonTicket> _complete(
    AudioLessonTicket t,
    VoicePlaybackResult proof,
    bool Function() current,
  ) => _run(t.owner, () async {
    if (!current() || proof.playbackCompleted == null) {
      throw StateError('No current completion');
    }
    await _admit(t);
    final latest = await _load(t);
    if (!current()) throw StateError('Playback retired');
    final count = t.completedSegments + 1;
    if (latest.completedSegments == count) return latest;
    if (latest.completedSegments != t.completedSegments ||
        count > t.segments.length) {
      throw StateError('Stale audio segment');
    }
    await _insert(t, count, proof);
    await _admit(t);
    if (!current()) throw StateError('Playback retired during checkpoint');
    return _load(t);
  }, t);

  VoiceAudioCache _lessonCache(AudioLessonTicket t) {
    if (!identical(_cacheOwner, t.owner)) {
      _cache?.retire();
      _watch?.cancel();
      _cacheOwner = t.owner;
      _cache = LessonAudioCache(
        requireCurrent: () async {
          if (_disposed || !isAvailable()) {
            throw StateError('Audio cache retired');
          }
          await sets.ownerGeneration.requireCurrentAsync(t.owner);
          if (_disposed || !isAvailable()) {
            throw StateError('Audio cache retired');
          }
        },
      );
      final captured = _cache;
      _watch = sets.watchOwnerCurrent(t.owner).listen((current) {
        if (!current) {
          captured?.retire();
          for (final p in _players.toList()) {
            if (identical(p.ticket.owner, t.owner)) p.close().ignore();
          }
        }
      });
    }
    return _cache!.lesson(t.contentHash);
  }

  AudioLessonPlayback player(AudioLessonTicket ticket) {
    final player = AudioLessonPlayback._(this, ticket);
    _players.add(player);
    return player;
  }

  Future<void> deleteCachedAudio(AudioLessonTicket ticket) async {
    await sets.ownerGeneration.requireCurrentAsync(ticket.owner);
    if (identical(_cacheOwner, ticket.owner)) {
      await _cache?.deleteLesson(ticket.contentHash);
    }
  }

  Future<Map<String, Object?>> exportArchive(OwnerGenerationToken owner) =>
      _run(
        owner,
        () async {
          final rows =
              await (database.select(database.audioLessonCheckpoints)
                    ..where((r) => r.ownerId.equals(owner.ownerId))
                    ..orderBy([
                      (r) => OrderingTerm.asc(r.activityId),
                      (r) => OrderingTerm.asc(r.revision),
                    ]))
                  .get();
          final content = <String, Object?>{
            'schemaVersion': 1,
            'ownerId': owner.ownerId,
            'records': [
              for (final r in rows)
                {
                  'activityId': r.activityId,
                  'revision': r.revision,
                  'operationId': r.operationId,
                  'payload': jsonDecode(r.payloadJson),
                },
            ],
          };
          return {
            ...content,
            'sha256': sha256
                .convert(utf8.encode(jsonEncode(content)))
                .toString(),
          };
        },
        null,
        false,
      );

  /// Local backup digest detects corruption, not authenticity. No restored
  /// record creates mastery or proves acoustic playback on this device.
  Future<void> restoreArchive(
    OwnerGenerationToken owner,
    Map<String, Object?> envelope,
  ) {
    final frozen = Map<String, Object?>.from(
      jsonDecode(jsonEncode(envelope)) as Map,
    );
    return _run(
      owner,
      () async {
        if (frozen.length != 4 ||
            frozen['schemaVersion'] is! int ||
            frozen['schemaVersion'] != 1 ||
            frozen['ownerId'] != owner.ownerId ||
            frozen['records'] is! List ||
            (frozen['records'] as List).length > 10000) {
          throw const FormatException('Invalid audio archive');
        }
        final body = {...frozen}..remove('sha256');
        if (sha256.convert(utf8.encode(jsonEncode(body))).toString() !=
            frozen['sha256']) {
          throw const FormatException('Audio archive checksum mismatch');
        }
        final counts = <String, int>{};
        final operations = <String>{};
        for (final raw in frozen['records'] as List) {
          if (raw is! Map ||
              raw.length != 4 ||
              raw['activityId'] is! String ||
              raw['revision'] is! int ||
              raw['operationId'] is! String ||
              raw['payload'] is! Map) {
            throw const FormatException('Invalid audio record');
          }
          final activity = raw['activityId'] as String,
              operation = raw['operationId'] as String;
          if (activity.isEmpty ||
              activity.trim() != activity ||
              activity.length > 200 ||
              RegExp(r'[\x00-\x1f\x7f]').hasMatch(activity)) {
            throw const FormatException('Invalid audio identity');
          }
          final revision = raw['revision'] as int;
          final payload = Map<String, Object?>.from(raw['payload'] as Map);
          if (payload.length != 3 ||
              payload['pin'] is! Map ||
              revision != (counts[activity] ?? 0) + 1 ||
              !operations.add(operation)) {
            throw const FormatException('Invalid checkpoint chain');
          }
          counts[activity] = revision;
          final pin = Map<String, Object?>.from(payload['pin'] as Map);
          if (pin['set'] is! Map ||
              pin['format'] is! String ||
              !AudioLessonFormat.values.any((f) => f.name == pin['format'])) {
            throw const FormatException('Invalid audio pin');
          }
          final set = PersonalSetRevision.fromJson(
            Map<String, Object?>.from(pin['set'] as Map),
          );
          final saved = await sets.repository.readExact(
            ownerId: owner.ownerId,
            setId: set.setId,
            revision: set.revision,
          );
          if (saved?.payloadHash != set.payloadHash) {
            throw StateError('Restore exact personal set first');
          }
          final ticket = AudioLessonTicket._(
            owner,
            set,
            AudioLessonFormat.values.byName(pin['format'] as String),
            activity,
            revision - 1,
          );
          if (jsonEncode(ticket.pin) != jsonEncode(pin) ||
              revision > ticket.segments.length + 1 ||
              operation != _operation(ticket, revision - 1) ||
              payload['completedSegments'] != revision - 1 ||
              (revision == 1
                  ? payload['playback'] != null
                  : !_validPlayback(payload['playback']))) {
            throw const FormatException('Invalid audio checkpoint');
          }
          final encoded = jsonEncode(payload);
          final prior =
              await (database.select(database.audioLessonCheckpoints)..where(
                    (r) =>
                        r.ownerId.equals(owner.ownerId) &
                        (r.operationId.equals(operation) |
                            (r.activityId.equals(activity) &
                                r.revision.equals(revision))),
                  ))
                  .get();
          if (prior.isNotEmpty) {
            if (prior.length != 1 ||
                prior.single.activityId != activity ||
                prior.single.operationId != operation ||
                prior.single.revision != revision ||
                prior.single.payloadJson != encoded) {
              throw StateError('Audio restore collision');
            }
          } else {
            await database
                .into(database.audioLessonCheckpoints)
                .insert(
                  AudioLessonCheckpointsCompanion.insert(
                    ownerId: owner.ownerId,
                    activityId: activity,
                    revision: revision,
                    operationId: operation,
                    payloadJson: encoded,
                  ),
                );
          }
          await _load(ticket);
        }
      },
      null,
      false,
    );
  }

  Future<void> retire() async {
    _cache?.retire();
    _cache = null;
    _cacheOwner = null;
    final watch = _watch;
    _watch = null;
    // Retire every ticket synchronously before awaiting stream cancellation.
    final drains = _players.toList().map((p) => p.close()).toList();
    await Future.wait<void>([if (watch != null) watch.cancel(), ...drains]);
  }

  Future<void> dispose() async {
    _disposed = true;
    await retire();
  }
}

enum AudioLessonPlaybackState {
  ready,
  playing,
  draining,
  paused,
  completed,
  textOnly,
  unavailable,
  cleanupFailed,
  closed,
}

final class AudioLessonPlayback extends ChangeNotifier {
  AudioLessonPlayback._(this._owner, AudioLessonTicket ticket)
    : _ticket = ticket,
      _cursor = ticket.completedSegments;
  final AudioLessonUseCases _owner;
  AudioLessonTicket _ticket;
  AudioLessonTicket get ticket => _ticket;
  AudioLessonPlaybackState _state = AudioLessonPlaybackState.ready;
  AudioLessonPlaybackState get state => _state;
  VoiceSession? _session;
  int _epoch = 0;
  int _cursor;
  Future<void>? _closeFuture;
  bool _closed = false, _notifierDisposed = false;
  Future<void> _cleanup = Future.value();
  void _notify() {
    if (!_notifierDisposed) notifyListeners();
  }

  bool _current(int epoch) => !_closed && epoch == _epoch;
  Future<void> playNext() async {
    if (_closed ||
        _state == AudioLessonPlaybackState.playing ||
        _state == AudioLessonPlaybackState.draining ||
        _state == AudioLessonPlaybackState.cleanupFailed) {
      return;
    }
    if (_cursor == ticket.segments.length) {
      _state = AudioLessonPlaybackState.completed;
      _notify();
      return;
    }
    final epoch = ++_epoch;
    _state = AudioLessonPlaybackState.playing;
    _notify();
    try {
      await _cleanup;
      await _owner.validate(ticket);
      if (!_current(epoch)) return;
      final voice = _owner.voice;
      if (voice == null) {
        _state = AudioLessonPlaybackState.textOnly;
        return;
      }
      if (_session?.isCurrent != true) _session = voice.acquireSession();
      final session = _session!;
      final segment = _cursor;
      final cache = _owner._lessonCache(ticket);
      final request = VoiceRequest.create(
        text: ticket.segments[segment],
        language: 'en',
        voiceId: 'teacher_female',
        speed: 1,
        contentId: '${ticket.contentHash}:$segment',
        contentType: 'audioLesson',
        mode: VoiceMode.practice,
        localOnly: true,
        lessonCache: cache,
      );
      final proof = await session.speakUntilCompleted(request);
      if (!_current(epoch) || !session.isCurrent) return;
      if (segment == ticket.completedSegments) {
        _ticket = await _owner._complete(
          ticket,
          proof,
          () => _current(epoch) && session.isCurrent,
        );
      }
      await _owner.validate(ticket);
      if (!_current(epoch)) return;
      _cursor = segment + 1;
      _state = _cursor == ticket.segments.length
          ? AudioLessonPlaybackState.completed
          : AudioLessonPlaybackState.ready;
    } on Object catch (error) {
      if (!_current(epoch)) return;
      try {
        await _session?.stop();
      } on Object {
        if (_current(epoch)) _state = AudioLessonPlaybackState.cleanupFailed;
        return;
      }
      if (_current(epoch)) {
        _state = error is VoiceFailure
            ? AudioLessonPlaybackState.textOnly
            : AudioLessonPlaybackState.unavailable;
      }
    } finally {
      _notify();
    }
  }

  Future<void> pause() {
    final epoch = ++_epoch;
    _state = AudioLessonPlaybackState.draining;
    _notify();
    final prior = _cleanup;
    final session = _session;
    final drain = () async {
      try {
        await prior;
        await session?.stop();
        if (epoch == _epoch) {
          _state = _closed
              ? AudioLessonPlaybackState.closed
              : AudioLessonPlaybackState.paused;
        }
      } on Object {
        if (epoch == _epoch) _state = AudioLessonPlaybackState.cleanupFailed;
        rethrow;
      } finally {
        _notify();
      }
    }();
    _cleanup = drain;
    drain.ignore();
    return drain;
  }

  Future<void> replay() async {
    if (_closed) return;
    await pause();
    await _owner.validate(ticket);
    if (_closed) return;
    _cursor = 0;
    _state = AudioLessonPlaybackState.ready;
    _notify();
  }

  Future<void> retryCleanup() async {
    if (_closed || _state != AudioLessonPlaybackState.cleanupFailed) return;
    final epoch = ++_epoch;
    _state = AudioLessonPlaybackState.draining;
    _notify();
    try {
      // A new successful owned stop is the only way to replace a failed barrier.
      await _session?.stop();
      if (!_current(epoch)) return;
      _cleanup = Future.value();
      _state = AudioLessonPlaybackState.paused;
    } on Object {
      if (_current(epoch)) _state = AudioLessonPlaybackState.cleanupFailed;
      rethrow;
    } finally {
      _notify();
    }
  }

  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    _closed = true;
    ticket.cancel();
    try {
      await pause();
      await _session?.release();
    } finally {
      _owner._players.remove(this);
    }
  }

  @override
  void dispose() {
    _notifierDisposed = true;
    close().ignore();
    super.dispose();
  }
}
