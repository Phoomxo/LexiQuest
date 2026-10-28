import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Displays a permission error with an optional "open settings" button
/// when the permission was permanently denied.
class PermissionErrorWidget extends StatelessWidget {
  const PermissionErrorWidget({
    super.key,
    required this.message,
    required this.isPermanentlyDenied,
    this.onRetry,
  });

  final String message;
  final bool isPermanentlyDenied;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.privacy_tip_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              key: const ValueKey('permission-error-message'),
            ),
            const SizedBox(height: 24),
            if (isPermanentlyDenied)
              FilledButton.icon(
                key: const ValueKey('open-settings'),
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings),
                label: const Text('เปิดการตั้งค่า'),
              )
            else if (onRetry != null)
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('ลองอีกครั้ง'),
              ),
          ],
        ),
      ),
    );
  }
}
