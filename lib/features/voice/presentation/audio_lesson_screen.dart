import 'dart:async';
import 'package:flutter/material.dart';
import '../../../navigation/app_routes.dart';
import '../../../runtime/app_dependencies.dart';
import '../../identity/application/owner_generation.dart';
import '../../learning_packs/domain/personal_sets.dart';
import '../application/audio_lesson_use_cases.dart';
import '../domain/audio_lesson.dart';

class AudioLessonScreen extends StatefulWidget {
  const AudioLessonScreen({
    super.key,
    required this.useCases,
    required this.owner,
    required this.set,
  });
  final AudioLessonUseCases useCases;
  final OwnerGenerationToken owner;
  final PersonalSetRevision set;
  @override
  State<AudioLessonScreen> createState() => _AudioLessonScreenState();
}

class _AudioLessonScreenState extends State<AudioLessonScreen>
    with WidgetsBindingObserver, RouteAware {
  AudioLessonPlayback? _player;
  StreamSubscription<bool>? _watch;
  Listenable? _features;
  PageRoute<dynamic>? _route;
  bool _retired = false, _loading = false;
  int _epoch = 0;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watch = widget.useCases.sets.watchOwnerCurrent(widget.owner).listen((
      current,
    ) {
      if (!current) _retire();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
    final features = AppDependenciesScope.maybeOf(context)?.features;
    final changes = features is Listenable ? features as Listenable : null;
    if (!identical(_features, changes)) {
      _features?.removeListener(_featureChanged);
      _features = changes;
      _features?.addListener(_featureChanged);
    }
    if (!widget.useCases.isAvailable()) _retire();
  }

  void _featureChanged() {
    if (!widget.useCases.isAvailable()) _retire();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _retire() {
    if (_retired) return;
    _retired = true;
    _epoch++;
    _loading = false;
    _player?.removeListener(_changed);
    _player?.dispose();
    _player = null;
    widget.useCases.retire().ignore();
    if (mounted) setState(() {});
  }

  @override
  void didPushNext() {
    _player?.pause().ignore();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      if (_player == null) {
        _retire();
      } else {
        _player?.pause().ignore();
      }
    }
  }

  Future<void> _open(AudioLessonFormat format) async {
    if (_retired || _loading) return;
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ticket = await widget.useCases.open(
        widget.owner,
        setId: widget.set.setId,
        setRevision: widget.set.revision,
        activityId: 'audio:${widget.set.payloadHash}:${format.name}',
        format: format,
      );
      if (!mounted || _retired || epoch != _epoch) {
        ticket.cancel();
        return;
      }
      _player = widget.useCases.player(ticket)..addListener(_changed);
    } on Object {
      if (mounted && epoch == _epoch) {
        _error = 'Reviewed audio content is unavailable for this set.';
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  Future<void> _deleteCache() async {
    final player = _player;
    if (player == null) return;
    try {
      await player.pause();
      await widget.useCases.deleteCachedAudio(player.ticket);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Audio cleanup is incomplete. Return to your set.',
        );
      }
    }
  }

  @override
  void dispose() {
    _epoch++;
    _watch?.cancel();
    _features?.removeListener(_featureChanged);
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _player?.removeListener(_changed);
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final busy =
        player?.state == AudioLessonPlaybackState.playing ||
        player?.state == AudioLessonPlaybackState.draining;
    return Scaffold(
      appBar: AppBar(title: const Text('Audio lesson')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_retired)
            const Text('Session closed. Return to your set to reopen.')
          else ...[
            Text(
              widget.set.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Text(
              'Listening is exposure, not mastery. It does not award points or change review schedules.',
            ),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            if (_loading) const Text('Loading reviewed script…'),
            if (player == null && !_loading) ...[
              const Text('Choose a format'),
              FilledButton(
                onPressed: () => _open(AudioLessonFormat.wordAndExample),
                child: const Text('Word and example'),
              ),
              OutlinedButton(
                onPressed: () => _open(AudioLessonFormat.shortScenario),
                child: const Text('Short scenario'),
              ),
            ],
            if (player != null) ...[
              const Text(
                'Resume replays the interrupted segment from its start. No exact seek or word highlighting.',
              ),
              Text(
                'Completed segments: ${player.ticket.completedSegments} / ${player.ticket.segments.length}',
              ),
              Semantics(
                liveRegion: true,
                child: Text(switch (player.state) {
                  AudioLessonPlaybackState.playing => 'Playing segment…',
                  AudioLessonPlaybackState.draining =>
                    'Stopping audio; waiting for cleanup…',
                  AudioLessonPlaybackState.textOnly =>
                    'Text only · audio completion unavailable. Read the transcript or retry.',
                  AudioLessonPlaybackState.unavailable =>
                    'Audio lesson unavailable. Return to your set.',
                  AudioLessonPlaybackState.cleanupFailed =>
                    'Audio cleanup incomplete. Playback is blocked.',
                  AudioLessonPlaybackState.completed =>
                    'Listening complete · exposure only.',
                  AudioLessonPlaybackState.paused =>
                    'Paused · resume starts the incomplete segment again.',
                  AudioLessonPlaybackState.closed => 'Session closed.',
                  _ => 'Ready to listen',
                }),
              ),
              FilledButton(
                key: const Key('audio-play'),
                onPressed: busy ? null : player.playNext,
                child: const Text('Play next / resume segment'),
              ),
              OutlinedButton(
                key: const Key('audio-pause'),
                onPressed: () => player.pause().ignore(),
                child: const Text('Pause / stop audio'),
              ),
              if (player.state == AudioLessonPlaybackState.cleanupFailed)
                OutlinedButton(
                  onPressed: () => player.retryCleanup().ignore(),
                  child: const Text('Retry audio cleanup'),
                ),
              TextButton(
                onPressed: busy ? null : () => player.replay().ignore(),
                child: const Text('Replay from start'),
              ),
              TextButton(
                onPressed: _deleteCache,
                child: const Text('Delete cached audio'),
              ),
              const Text(
                'Audio cache: up to 20 MiB / 10 lessons, oldest used first. Temporary; cleared when the owner changes or the app closes.',
              ),
              const Divider(),
              Text('Transcript', style: Theme.of(context).textTheme.titleLarge),
              for (var i = 0; i < player.ticket.segments.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('${i + 1}. ${player.ticket.segments[i]}'),
                ),
            ],
          ],
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Return to set for practice'),
          ),
        ],
      ),
    );
  }
}
