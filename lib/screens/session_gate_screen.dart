import 'package:flutter/material.dart';

import '../account/account_gateway.dart';
import '../account/account_models.dart';
import '../account/account_profile_provisioner.dart';
import 'login_screen.dart';
import 'main_navigation_screen.dart';
import 'otp_screen.dart';
import 'register_screen.dart';
import '../services/guest_session_service.dart';

final class SessionGateScreen extends StatelessWidget {
  const SessionGateScreen({
    super.key,
    required this.accountGateway,
    required this.guestSessionService,
    required this.guestUpgradeHandoff,
    this.profileProvisioner = const UnavailableAccountProfileProvisioner(),
  });

  final AccountGateway accountGateway;
  final GuestSessionService guestSessionService;
  final GuestUpgradeHandoff guestUpgradeHandoff;
  final AccountProfileProvisioning profileProvisioner;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AccountSession?>(
      stream: accountGateway.authStateChanges(),
      initialData: accountGateway.currentSession,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final session = snapshot.data;
        if (session == null) {
          return LoginScreen(
            accountGateway: accountGateway,
            guestSessionService: guestSessionService,
          );
        }
        if (session.isAnonymous) {
          return const MainNavigationScreen();
        }
        return _ProvisioningGate(
          key: ValueKey<String>(session.uid),
          session: session,
          accountGateway: accountGateway,
          profileProvisioner: profileProvisioner,
          guestUpgradeHandoff: guestUpgradeHandoff,
        );
      },
    );
  }
}

final class _ProvisioningGate extends StatefulWidget {
  const _ProvisioningGate({
    super.key,
    required this.session,
    required this.accountGateway,
    required this.profileProvisioner,
    required this.guestUpgradeHandoff,
  });

  final AccountSession session;
  final AccountGateway accountGateway;
  final AccountProfileProvisioning profileProvisioner;
  final GuestUpgradeHandoff guestUpgradeHandoff;

  @override
  State<_ProvisioningGate> createState() => _ProvisioningGateState();
}

final class _ProvisioningGateState extends State<_ProvisioningGate> {
  late Future<AccountProvisioningState> _state = _loadState();

  Future<AccountProvisioningState> _loadState() async {
    try {
      return await widget.profileProvisioner.provisioningState(
        widget.session.uid,
      );
    } on Object {
      return AccountProvisioningState.unavailable;
    }
  }

  void _retry() {
    final nextState = _loadState();
    setState(() {
      _state = nextState;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AccountProvisioningState>(
      future: _state,
      builder: (context, completion) {
        if (completion.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return switch (completion.data ??
            AccountProvisioningState.unavailable) {
          AccountProvisioningState.incomplete => RegisterScreen(
            accountGateway: widget.accountGateway,
            profileProvisioner: widget.profileProvisioner,
            recoveredSession: widget.session,
            guestUpgradeHandoff: widget.guestUpgradeHandoff,
          ),
          AccountProvisioningState.complete =>
            widget.session.isEmailVerified
                ? const MainNavigationScreen()
                : OTPScreen(
                    email: widget.session.email ?? '',
                    accountGateway: widget.accountGateway,
                    profileProvisioner: widget.profileProvisioner,
                  ),
          AccountProvisioningState.unavailable => Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'ยังตรวจสอบการตั้งค่าบัญชีไม่ได้ โปรดเชื่อมต่ออินเทอร์เน็ตแล้วลองอีกครั้ง',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const ValueKey<String>('provisioning-retry'),
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('ลองอีกครั้ง'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        };
      },
    );
  }
}
