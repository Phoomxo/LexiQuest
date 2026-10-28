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
    required this.sessionId,
    this.repository,
    this.isFromFirestore = true,
    this.selectedCategoryId,
  });

  final int correctAnswers;
  final int wrongAnswers;
  final String sessionId;
  final ProgressRepository? repository;
  final bool isFromFirestore;
  final String? selectedCategoryId;

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> {
  Future<_PersistenceResult>? _persistenceFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_persistenceFuture != null) return;
    final repository =
        widget.repository ??
        AppDependenciesScope.maybeOf(context)?.progressRepository;
    _persistenceFuture = repository == null
        ? Future.value(const _PersistenceResult.notSaved())
        : _recordAndRead(repository);
  }

  Future<_PersistenceResult> _recordAndRead(
    ProgressRepository repository,
  ) async {
    try {
      await repository.recordSession(
        ProgressSession(
          sessionId: widget.sessionId,
          correctAnswers: widget.correctAnswers,
          wrongAnswers: widget.wrongAnswers,
        ),
      );
    } catch (_) {
      return const _PersistenceResult.notSaved();
    }

    try {
      return _PersistenceResult.saved(await repository.readSnapshot());
    } catch (_) {
      return const _PersistenceResult.savedWithoutSnapshot();
    }
  }

  @override
  Widget build(BuildContext context) {
    final persistenceFuture = _persistenceFuture;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ผลลัพธ์ของคุณ',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.deepPurple, Colors.indigo],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            elevation: 5,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'รอบนี้: ตอบถูก ${widget.correctAnswers} • '
                'ตอบผิด ${widget.wrongAnswers}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<_PersistenceResult>(
            future: persistenceFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Text(
                  'กำลังบันทึกผลรอบนี้ในอุปกรณ์…',
                  textAlign: TextAlign.center,
                );
              }
              return _buildPersistenceResult(
                snapshot.data ?? const _PersistenceResult.notSaved(),
              );
            },
          ),
          const SizedBox(height: 24),
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
                icon: const Icon(Icons.replay, color: Colors.white),
                label: const Text(
                  'เล่นใหม่',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
                icon: const Icon(Icons.home, color: Colors.white),
                label: const Text(
                  'กลับหน้าหลัก',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPersistenceResult(_PersistenceResult persistence) {
    switch (persistence.outcome) {
      case _PersistenceOutcome.notSaved:
        return const Text(
          'ยังไม่ได้บันทึกผลรอบนี้ในอุปกรณ์',
          textAlign: TextAlign.center,
        );
      case _PersistenceOutcome.savedWithoutSnapshot:
        return const Text(
          'บันทึกผลรอบนี้แล้ว แต่ยังอ่านยอดรวมจากอุปกรณ์ไม่ได้',
          textAlign: TextAlign.center,
        );
      case _PersistenceOutcome.saved:
        final progress = persistence.snapshot!;
        return Column(
          children: [
            const Text(
              'บันทึกผลแล้ว: ความคืบหน้าการฝึกอยู่เฉพาะอุปกรณ์นี้',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildStatCard(
              'แต้มฝึกสะสม (เฉพาะอุปกรณ์นี้ • ใช้จ่ายไม่ได้)',
              progress.totalPoints.toString(),
              Icons.stars,
              Colors.amber.shade800,
            ),
            _buildStatCard(
              'จำนวนครั้งที่เล่น (เฉพาะอุปกรณ์นี้ • ใช้จ่ายไม่ได้)',
              progress.gamesPlayed.toString(),
              Icons.history,
              Colors.deepPurple,
            ),
            _buildStatCard(
              'ตอบถูกทั้งหมด (เฉพาะอุปกรณ์นี้ • ใช้จ่ายไม่ได้)',
              progress.totalCorrectAnswers.toString(),
              Icons.check_circle,
              Colors.green,
            ),
            _buildStatCard(
              'ตอบผิดทั้งหมด (เฉพาะอุปกรณ์นี้ • ใช้จ่ายไม่ได้)',
              progress.totalWrongAnswers.toString(),
              Icons.cancel,
              Colors.red,
            ),
          ],
        );
    }
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: ListTile(
        leading: Icon(icon, color: color, size: 30),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        trailing: Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

enum _PersistenceOutcome { notSaved, saved, savedWithoutSnapshot }

class _PersistenceResult {
  const _PersistenceResult.saved(this.snapshot)
    : outcome = _PersistenceOutcome.saved;

  const _PersistenceResult.notSaved()
    : snapshot = null,
      outcome = _PersistenceOutcome.notSaved;

  const _PersistenceResult.savedWithoutSnapshot()
    : snapshot = null,
      outcome = _PersistenceOutcome.savedWithoutSnapshot;

  final ProgressSnapshot? snapshot;
  final _PersistenceOutcome outcome;
}
