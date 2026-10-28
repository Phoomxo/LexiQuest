import 'package:flutter/material.dart';

import '../account/account_cooldown.dart';
import '../account/account_error_mapper.dart';
import '../account/account_gateway.dart';
import '../account/account_profile_provisioner.dart';
import '../navigation/app_route.dart';

class OTPScreen extends StatefulWidget {
  const OTPScreen({
    super.key,
    required this.email,
    this.accountGateway,
    this.profileProvisioner = const UnavailableAccountProfileProvisioner(),
    this.resendCooldown,
  });

  final String email;
  final AccountGateway? accountGateway;
  final AccountProfileProvisioning profileProvisioner;
  final AccountCooldown? resendCooldown;

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  late final AccountCooldown _cooldown =
      widget.resendCooldown ?? AccountCooldown();
  bool _isLoading = false;

  Future<void> _refreshVerification() async {
    final gateway = widget.accountGateway;
    if (gateway == null || _isLoading) return;
    setState(() => _isLoading = true);
    try {
      final session = await gateway.reloadSession();
      if (!mounted) return;
      if (session?.isEmailVerified ?? false) {
        final provisioningState = await widget.profileProvisioner
            .provisioningState(session!.uid);
        if (!mounted) return;
        if (provisioningState == AccountProvisioningState.incomplete) {
          Navigator.of(context).pushReplacementNamed(
            AppRoute.register.path,
            arguments: RegisterRouteArgs(
              uid: session.uid,
              email: session.email ?? widget.email,
            ),
          );
          return;
        }
        if (provisioningState == AccountProvisioningState.unavailable) {
          _showMessage(AccountErrorMapper.messageFor('network-request-failed'));
          return;
        }
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(AppRoute.home.path, (_) => false);
      } else {
        _showMessage(
          'อีเมลยังไม่ได้รับการยืนยัน กรุณาตรวจสอบกล่องจดหมายแล้วลองใหม่',
        );
      }
    } on AccountOperationException catch (error) {
      if (mounted) _showMessage(AccountErrorMapper.messageFor(error.code));
    } on Object {
      if (mounted) _showMessage(AccountErrorMapper.messageFor('unknown'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendVerification() async {
    final gateway = widget.accountGateway;
    if (gateway == null || _isLoading) return;
    if (!_cooldown.canSubmit) {
      _showMessage(
        'กรุณารอ ${_cooldown.remaining.inSeconds} วินาทีก่อนส่งอีเมลอีกครั้ง',
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await gateway.sendVerificationEmail();
      _cooldown.start();
      if (mounted) {
        _showMessage('ส่งอีเมลยืนยันอีกครั้งแล้ว กรุณาตรวจสอบกล่องจดหมาย');
      }
    } on AccountOperationException catch (error) {
      if (mounted) _showMessage(AccountErrorMapper.messageFor(error.code));
    } on Object {
      if (mounted) _showMessage(AccountErrorMapper.messageFor('unknown'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ยืนยันอีเมล')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.mark_email_unread_outlined, size: 72),
              const SizedBox(height: 16),
              const Text(
                'ตรวจสอบอีเมลเพื่อยืนยันบัญชี',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'เราได้ส่งลิงก์ยืนยันไปที่ ${widget.email}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const ValueKey<String>('verify-refresh'),
                onPressed: _isLoading ? null : _refreshVerification,
                icon: const Icon(Icons.refresh),
                label: const Text('ฉันยืนยันอีเมลแล้ว'),
              ),
              TextButton.icon(
                key: const ValueKey<String>('verify-resend'),
                onPressed: _isLoading ? null : _resendVerification,
                icon: const Icon(Icons.email_outlined),
                label: const Text('ส่งอีเมลยืนยันอีกครั้ง'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
