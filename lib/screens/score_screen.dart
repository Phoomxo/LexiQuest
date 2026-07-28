import 'dart:math';

import 'package:flutter/material.dart';

import '../progress/progress_repository.dart';
import '../runtime/app_dependencies.dart';
import 'choose_mode_screen.dart';
import 'main_navigation_screen.dart';

class ScoreScreen extends StatefulWidget {
  const ScoreScreen({
    super.key,
    required this.correctAnswers,
    required this.wrongAnswers,
    this.sessionId,
    this.repository,
    this.isFromFirestore = true,
    this.selectedCategoryId,
  });

  final int correctAnswers;
  final int wrongAnswers;
  final String? sessionId;
  final ProgressRepository? repository;
  final bool isFromFirestore;
  final String? selectedCategoryId;

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> {
  late final String _sessionId;
  Future<_PersistenceResult>? _persistenceFuture;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId ?? _newLegacySessionId();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_persistenceFuture != null) return;
    final repository =
        widget.repository ??
        AppDependenciesScope.maybeOf(context)?.progressRepository;
    _persistenceFuture = repository == null
        ? Future.value(const _PersistenceResult.unavailable())
        : _recordAndRead(repository);
  }

  Future<_PersistenceResult> _recordAndRead(
    ProgressRepository repository,
  ) async {
    try {
      await repository.recordSession(
        ProgressSession(
          sessionId: _sessionId,
          correctAnswers: widget.correctAnswers,
          wrongAnswers: widget.wrongAnswers,
        ),
      );
      return _PersistenceResult.saved(await repository.readSnapshot());
    } catch (_) {
      return const _PersistenceResult.unavailable();
    }
  }

  String _newLegacySessionId() {
    final random = Random.secure();
    return 'legacy-score-${DateTime.now().microsecondsSinceEpoch}-'
        '${random.nextInt(1 << 32).toRadixString(16)}-'
        '${random.nextInt(1 << 32).toRadixString(16)}';
  }

  @override
  Widget build(BuildContext context) {
    final persistenceFuture = _persistenceFuture;
    if (persistenceFuture == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return FutureBuilder<_PersistenceResult>(
      future: persistenceFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final persistence =
            snapshot.data ?? const _PersistenceResult.unavailable();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Quiz results'),
            centerTitle: true,
            backgroundColor: Colors.deepPurple,
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'This session: ${widget.correctAnswers} correct, '
                  '${widget.wrongAnswers} wrong',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 16),
                if (!persistence.isSaved)
                  const Text('Local progress totals are unavailable.')
                else ...[
                  _buildStatCard(
                    'Total points',
                    persistence.snapshot!.totalPoints.toString(),
                    Icons.stars,
                    Colors.amber.shade800,
                  ),
                  _buildStatCard(
                    'Games played',
                    persistence.snapshot!.gamesPlayed.toString(),
                    Icons.history,
                    Colors.deepPurple,
                  ),
                  _buildStatCard(
                    'Correct answers',
                    persistence.snapshot!.totalCorrectAnswers.toString(),
                    Icons.check_circle,
                    Colors.green,
                  ),
                  _buildStatCard(
                    'Wrong answers',
                    persistence.snapshot!.totalWrongAnswers.toString(),
                    Icons.cancel,
                    Colors.red,
                  ),
                ],
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ChooseModeScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.replay),
                      label: const Text('Play again'),
                    ),
                    const SizedBox(width: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MainNavigationScreen(),
                          ),
                          (route) => false,
                        );
                      },
                      icon: const Icon(Icons.home),
                      label: const Text('Home'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        trailing: Text(value),
      ),
    );
  }
}

class _PersistenceResult {
  const _PersistenceResult.saved(this.snapshot) : isSaved = true;

  const _PersistenceResult.unavailable() : snapshot = null, isSaved = false;

  final ProgressSnapshot? snapshot;
  final bool isSaved;
}
