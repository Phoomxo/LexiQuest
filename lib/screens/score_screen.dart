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
  Future<ProgressSnapshot>? _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId ?? _newLegacySessionId();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_snapshotFuture != null) return;
    final repository =
        widget.repository ??
        AppDependenciesScope.maybeOf(context)?.progressRepository;
    if (repository != null) {
      _snapshotFuture = _recordAndRead(repository);
    }
  }

  Future<ProgressSnapshot> _recordAndRead(ProgressRepository repository) async {
    await repository.recordSession(
      ProgressSession(
        sessionId: _sessionId,
        correctAnswers: widget.correctAnswers,
        wrongAnswers: widget.wrongAnswers,
      ),
    );
    return repository.readSnapshot();
  }

  String _newLegacySessionId() {
    final random = Random.secure();
    return 'legacy-score-${DateTime.now().microsecondsSinceEpoch}-'
        '${random.nextInt(1 << 32).toRadixString(16)}-'
        '${random.nextInt(1 << 32).toRadixString(16)}';
  }

  ProgressSnapshot get _unpersistedSnapshot => ProgressSnapshot(
    totalPoints: widget.correctAnswers,
    totalCorrectAnswers: widget.correctAnswers,
    totalWrongAnswers: widget.wrongAnswers,
    gamesPlayed: 1,
  );

  @override
  Widget build(BuildContext context) {
    final snapshotFuture =
        _snapshotFuture ?? Future.value(_unpersistedSnapshot);
    return FutureBuilder<ProgressSnapshot>(
      future: snapshotFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final progress = snapshot.data ?? _unpersistedSnapshot;
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
                _buildStatCard(
                  'Total points',
                  progress.totalPoints.toString(),
                  Icons.stars,
                  Colors.amber.shade800,
                ),
                _buildStatCard(
                  'Games played',
                  progress.gamesPlayed.toString(),
                  Icons.history,
                  Colors.deepPurple,
                ),
                _buildStatCard(
                  'Correct answers',
                  progress.totalCorrectAnswers.toString(),
                  Icons.check_circle,
                  Colors.green,
                ),
                _buildStatCard(
                  'Wrong answers',
                  progress.totalWrongAnswers.toString(),
                  Icons.cancel,
                  Colors.red,
                ),
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
