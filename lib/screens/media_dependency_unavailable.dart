import 'package:flutter/material.dart';

enum MediaDependencyUnavailableReason { voice, speechPractice, objectScanner }

/// Typed fail-closed state for media routes whose runtime-owned dependency is
/// absent. No platform fallback is constructed by an individual screen.
final class MediaDependencyUnavailable extends StatelessWidget {
  const MediaDependencyUnavailable({super.key, required this.reason});

  final MediaDependencyUnavailableReason reason;

  @override
  Widget build(BuildContext context) {
    void chooseAlternative() {
      Navigator.maybePop(context);
    }

    return Scaffold(
      key: const ValueKey<String>('media-dependency-unavailable'),
      appBar: AppBar(title: const Text('Practice unavailable')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'This practice activity is not available on this device right '
                'now. Your saved learning data is unchanged.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Semantics(
                container: true,
                button: true,
                label: 'Choose a non-media activity',
                onTap: chooseAlternative,
                child: ExcludeSemantics(
                  child: OutlinedButton.icon(
                    onPressed: chooseAlternative,
                    icon: const Icon(Icons.arrow_back_outlined),
                    label: const Text('Choose another activity'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
