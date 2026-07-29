import 'package:flutter/material.dart';

/// Placeholder retained for route compatibility while the remote economy is
/// disabled. Purchases will return only after a trusted server-side writer is
/// available.
class ShopPage extends StatelessWidget {
  const ShopPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Shop is currently unavailable.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
