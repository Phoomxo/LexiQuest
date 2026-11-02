import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/m3_theme.dart';
import '../../../runtime/app_dependencies.dart';
import '../../../widgets/adaptive_content_pane.dart';
import '../application/billing_use_cases.dart';
import '../domain/billing_contracts.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, this.billing});
  final BillingUseCases? billing;
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen>
    with WidgetsBindingObserver {
  StreamSubscription<BillingView>? _changes;
  BillingView _view = BillingView(phase: BillingPhase.unavailable);
  BillingUseCases? _billing;
  AppDependencies? _boundDependencies;
  bool _dependenciesBound = false;
  bool _retired = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_retired) return;
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (!_dependenciesBound) {
      _dependenciesBound = true;
      _boundDependencies = dependencies;
      _billing = widget.billing ?? dependencies?.billing;
      if (dependencies != null && !identical(dependencies.billing, _billing)) {
        _retire();
      } else {
        _observe();
      }
    } else if (!identical(dependencies, _boundDependencies)) {
      _retire();
    }
  }

  void _retire() {
    _retired = true;
    _billing = null;
    unawaited(_changes?.cancel());
    setState(
      () => _view = BillingView(
        phase: BillingPhase.unavailable,
        failure: BillingFailureCode.ownerChanged,
      ),
    );
  }

  bool _canUse(BillingUseCases billing) =>
      mounted && !_retired && identical(_billing, billing);

  void _observe() {
    final billing = _billing;
    _view = billing?.view ?? BillingView(phase: BillingPhase.unavailable);
    _changes = billing?.changes.listen((view) {
      if (_canUse(billing)) setState(() => _view = view);
    });
    if (billing != null) unawaited(_run(billing, billing.load));
  }

  @override
  void didUpdateWidget(SubscriptionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.billing, oldWidget.billing)) {
      if (_retired) return;
      unawaited(_changes?.cancel());
      _billing = widget.billing ?? _boundDependencies?.billing;
      if (_boundDependencies != null &&
          !identical(_boundDependencies?.billing, _billing)) {
        _retire();
        return;
      }
      _observe();
    }
  }

  Future<void> _run(
    BillingUseCases billing,
    Future<void> Function() command,
  ) async {
    if (!_canUse(billing)) return;
    try {
      await command();
    } on Object {
      // Commands publish their failure before completing with an error.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final billing = _billing;
    if (state == AppLifecycleState.resumed && billing != null && !_view.busy) {
      unawaited(_run(billing, billing.load));
    }
  }

  String _period(String value) {
    final match = RegExp(r'^P([1-9][0-9]*)([DWMY])$').firstMatch(value);
    if (match == null) return 'รอบ $value';
    final unit = switch (match.group(2)) {
      'D' => 'วัน',
      'W' => 'สัปดาห์',
      'M' => 'เดือน',
      _ => 'ปี',
    };
    return '${match.group(1)} $unit';
  }

  String _message() {
    if (_retired) return 'ข้อมูลผู้ใช้เปลี่ยนแล้ว กรุณากลับไปเปิดหน้านี้ใหม่';
    if (_billing == null) return 'ยังไม่เปิดรับชำระเงินในแอปรุ่นนี้';
    if (_view.failure case final failure?) {
      return switch (failure) {
        BillingFailureCode.accountRequired =>
          'โปรดเข้าสู่ระบบด้วยบัญชีที่ลงทะเบียนก่อนจัดการแพ็กเกจ',
        BillingFailureCode.ownerChanged =>
          'บัญชีเปลี่ยนแล้ว โปรดโหลดสิทธิ์ของบัญชีปัจจุบันอีกครั้ง',
        BillingFailureCode.cancelled => 'ยกเลิกการซื้อแล้ว',
        BillingFailureCode.pending =>
          'การซื้อยังรอดำเนินการ โปรดตรวจสอบใน Google Play',
        BillingFailureCode.purchaseDenied =>
          'ยังยืนยันการซื้อนี้ให้บัญชีปัจจุบันไม่ได้ โปรดตรวจสอบบัญชีที่ใช้ซื้อ',
        BillingFailureCode.verificationRequired =>
          'โปรดตรวจสอบหรือกู้คืนการซื้อเพื่ออัปเดตสิทธิ์',
        BillingFailureCode.quota => 'ใช้โควตาปัจจุบันครบแล้ว',
        BillingFailureCode.retryLater =>
          'ส่งคำขอตรวจสอบถี่เกินไป โปรดรอสักครู่แล้วลองอีกครั้ง',
        _ => 'ยังเชื่อมต่อระบบแพ็กเกจไม่ได้ โปรดลองใหม่ภายหลัง',
      };
    }
    return switch (_view.phase) {
      BillingPhase.loading => 'กำลังอ่านแพ็กเกจและตรวจสอบสิทธิ์',
      BillingPhase.launching => 'กำลังเปิดหน้าชำระเงินของ Google Play',
      BillingPhase.pending => 'การซื้อรอดำเนินการ ยังไม่เปิดสิทธิ์จากสถานะนี้',
      BillingPhase.verifying => 'กำลังยืนยันการซื้อกับเซิร์ฟเวอร์',
      BillingPhase.restoring => 'กำลังกู้คืนและตรวจสอบการซื้อ',
      BillingPhase.active => 'ตรวจสอบสิทธิ์แพ็กเกจแล้ว',
      BillingPhase.ready => 'เลือกแพ็กเกจที่ต้องการ หรือกู้คืนการซื้อเดิม',
      _ => 'ยังไม่มีข้อมูลแพ็กเกจที่ยืนยันได้',
    };
  }

  @override
  Widget build(BuildContext context) {
    final billing = _billing;
    final snapshot = _view.snapshot;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'แพ็กเกจและการซื้อ'),
      ),
      body: AdaptiveContentPane(
        maxWidth: AdaptiveContentPane.formMaxWidth,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Semantics(
              liveRegion: true,
              child: Text(_message(), key: const ValueKey('billing-status')),
            ),
            const SizedBox(height: 12),
            const Text('ฝึกออฟไลน์พื้นฐานได้โดยไม่ต้องสมัครสมาชิก'),
            if (_view.busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(
                semanticsLabel: 'กำลังดำเนินการกับระบบแพ็กเกจ',
              ),
            ],
            if (snapshot != null && _view.phase == BillingPhase.active) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'สิทธิ์ที่ยืนยันจากเซิร์ฟเวอร์',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${snapshot.grants.map((grant) => grant.entitlement).toSet().length} รายการ',
                      ),
                      if (snapshot.acknowledgementPending)
                        const Text(
                          'กำลังยืนยันใบซื้อให้ครบ โปรดตรวจสอบอีกครั้ง',
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (snapshot?.refreshRequired == true) ...[
              const SizedBox(height: 12),
              const Text('สิทธิ์บางส่วนต้องตรวจสอบการซื้อใหม่'),
            ],
            for (final offer in _view.offers)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        offer.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${offer.localizedPrice} ต่อ ${_period(offer.billingPeriod)}',
                      ),
                      for (final product
                          in _view.catalog?.products ??
                              const <BillingProduct>[])
                        if (product.productId == offer.productId &&
                            product.basePlanId == offer.basePlanId) ...[
                          const SizedBox(height: 8),
                          Text(
                            'สร้างเนื้อหา AI ได้ ${product.dailyManagedUnits} หน่วยต่อวัน',
                          ),
                          const Text('โควตาเริ่มรอบใหม่เวลา 00:00 UTC'),
                          const Text(
                            'หน่วยนับจากคำขอใหม่ที่บริการรับดำเนินการ รวมคำขอที่กำลังยืนยันผล',
                          ),
                        ],
                      const SizedBox(height: 8),
                      const Text(
                        'ต่ออายุอัตโนมัติ จัดการหรือยกเลิกได้ใน Google Play การยกเลิกจะมีผลตามรอบชำระเงิน',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: ValueKey('billing-buy-${offer.offerKey}'),
                        onPressed:
                            billing == null ||
                                _view.busy ||
                                _view.phase == BillingPhase.pending ||
                                _view.verificationPending
                            ? null
                            : () => _run(
                                billing,
                                () => billing.buy(
                                  offer,
                                  stillCurrent: () => _canUse(billing),
                                ),
                              ),
                        icon: const Icon(Icons.shopping_bag_outlined),
                        label: const Text('สมัครผ่าน Google Play'),
                      ),
                    ],
                  ),
                ),
              ),
            if (!_view.busy && _view.offers.isEmpty && _view.catalog != null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('ไม่มีแพ็กเกจที่ซื้อได้จาก Google Play ในขณะนี้'),
              ),
            const SizedBox(height: 16),
            if (billing != null) ...[
              OutlinedButton.icon(
                key: const ValueKey('billing-restore'),
                onPressed: _view.busy || _view.catalog == null
                    ? null
                    : () => _run(
                        billing,
                        () => billing.restore(
                          stillCurrent: () => _canUse(billing),
                        ),
                      ),
                icon: const Icon(Icons.restore),
                label: const Text('กู้คืนและตรวจสอบการซื้อเดิม'),
              ),
              if (_view.verificationPending)
                OutlinedButton(
                  key: const ValueKey('billing-retry-verification'),
                  onPressed: _view.busy
                      ? null
                      : () => _run(billing, billing.retryVerification),
                  child: const Text('ลองยืนยันใบซื้อเดิมอีกครั้ง'),
                ),
              TextButton(
                key: const ValueKey('billing-refresh'),
                onPressed: _view.busy
                    ? null
                    : () => _run(billing, billing.load),
                child: const Text('โหลดแพ็กเกจและสิทธิ์ใหม่'),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'ราคาที่ชำระจะแสดงและยืนยันใน Google Play สิทธิ์จะเปิดหลังเซิร์ฟเวอร์ตรวจสอบสำเร็จเท่านั้น',
            ),
            const SizedBox(height: 8),
            const Text(
              'แพ็กเกจนี้สำหรับสร้างเนื้อหา AI ผ่านบริการ LexiQuest การใช้ Gemini ด้วยคีย์ของคุณแยกจากแพ็กเกจนี้',
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
