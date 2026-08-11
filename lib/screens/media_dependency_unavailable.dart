import 'package:flutter/material.dart';

enum MediaDependencyUnavailableReason { voice, speechPractice, objectScanner }

/// Typed fail-closed state for media routes whose runtime-owned dependency is
/// absent. No platform fallback is constructed by an individual screen.
final class MediaDependencyUnavailable extends StatelessWidget {
  const MediaDependencyUnavailable({super.key, required this.reason});

  final MediaDependencyUnavailableReason reason;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey<String>('media-dependency-unavailable'),
      appBar: AppBar(title: const Text('Practice unavailable')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'This practice activity is not available on this device right '
            'now. Your saved learning data is unchanged.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
