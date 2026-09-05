import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';
import 'package:vocab_learning_app/features/research/presentation/research_participation_panel.dart';

// Deliberately NOT a valid signature/receipt. The widget transports opaque input;
// caller-owned validation is separately tested by the application layer.
const _document =
    '{"payload":"synthetic_private_owner",'
    '"signature":"synthetic_private_signature"}';

void main() {
  testWidgets('empty Thai panel is optional and does not fabricate approval', (
    tester,
  ) async {
    var imports = 0;
    var withdrawals = 0;
    var continuations = 0;
    await _pumpPanel(
      tester,
      onImport: (_) async => imports++,
      onWithdraw: () async => withdrawals++,
      onContinueLearning: () => continuations++,
    );
    expect(find.text('การเข้าร่วมการวิจัย (ไม่บังคับ)'), findsOneWidget);
    expect(find.text('ความยินยอม: ยังไม่พร้อม'), findsOneWidget);
    expect(find.text('การอนุญาตของผู้ปกครอง: ยังไม่พร้อม'), findsOneWidget);
    expect(find.text('ความสมัครใจของผู้เรียน: ยังไม่พร้อม'), findsOneWidget);
    expect(find.textContaining('ไม่กระทบการเรียน'), findsWidgets);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(RadioListTile<String>), findsNothing);
    expect(find.textContaining('ยืนยันจากภายนอกแล้ว'), findsNothing);
    expect(imports, 0);
    expect(withdrawals, 0);
    await _tap(tester, _action('continue'));
    expect(continuations, 1);
    expect(imports, 0);
    expect(withdrawals, 0);
  });

  testWidgets('English panel explains optionality, Skip and withdrawal', (
    tester,
  ) async {
    await _pumpPanel(tester, languageCode: 'en');
    expect(find.text('Optional research participation'), findsOneWidget);
    expect(find.text('Consent: Not ready'), findsOneWidget);
    expect(find.text('Continue learning'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.textContaining('does not affect learning'), findsWidgets);
    expect(find.textContaining('withdraw', findRichText: true), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(_input).decoration!.labelText,
      'Externally signed JSON document',
    );
  });

  testWidgets('Skip delegates only to continuation', (tester) async {
    var continuations = 0;
    var writes = 0;
    await _pumpPanel(
      tester,
      onImport: (_) async => writes++,
      onWithdraw: () async => writes++,
      onContinueLearning: () => continuations++,
    );
    await _tap(tester, _action('skip'));
    expect(continuations, 1);
    expect(writes, 0);
  });

  for (final language in ['th', 'en']) {
    testWidgets('$language adult status uses only the participant class code', (
      tester,
    ) async {
      await _pumpPanel(tester, permit: _permit(), languageCode: language);
      expect(
        find.text(
          language == 'th'
              ? 'กลุ่มผู้เข้าร่วม: adult'
              : 'Participant group: adult',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          language == 'th'
              ? 'ความยินยอม: ยืนยันจากภายนอกแล้ว'
              : 'Consent: Verified externally',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          language == 'th'
              ? 'การอนุญาตของผู้ปกครอง: ไม่จำเป็นสำหรับ adult'
              : 'Guardian permission: Not required for adult',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          language == 'th'
              ? 'ความสมัครใจของผู้เรียน: ไม่จำเป็นสำหรับ adult'
              : 'Learner assent: Not required for adult',
        ),
        findsOneWidget,
      );
      _expectNoPrivateText();
    });
  }

  for (final guardian in [false, true]) {
    for (final assent in [false, true]) {
      testWidgets('minor guardian=$guardian assent=$assent are independent', (
        tester,
      ) async {
        await _pumpPanel(
          tester,
          languageCode: 'en',
          permit: _permit(
            participantClass: ResearchParticipantClass.minor,
            guardian: guardian,
            assent: assent,
          ),
        );
        expect(find.text('Participant group: minor'), findsOneWidget);
        expect(
          find.text(
            'Guardian permission: ${guardian ? 'Verified externally' : 'Not ready'}',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Learner assent: ${assent ? 'Verified externally' : 'Not ready'}',
          ),
          findsOneWidget,
        );
        expect(find.byType(Checkbox), findsNothing);
        _expectNoPrivateText();
      });
    }
  }

  testWidgets('Thai minor statuses separately describe external verification', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      permit: _permit(
        participantClass: ResearchParticipantClass.minor,
        guardian: true,
      ),
    );
    expect(find.text('กลุ่มผู้เข้าร่วม: minor'), findsOneWidget);
    expect(
      find.text('การอนุญาตของผู้ปกครอง: ยืนยันจากภายนอกแล้ว'),
      findsOneWidget,
    );
    expect(find.text('ความสมัครใจของผู้เรียน: ยังไม่พร้อม'), findsOneWidget);
  });

  testWidgets('imports unchanged opaque JSON once and does not mint a permit', (
    tester,
  ) async {
    final calls = <String>[];
    await _pumpPanel(tester, onImport: (document) async => calls.add(document));
    const pasted = '  $_document\n';
    await _enterDocument(tester, pasted);
    expect(calls, isEmpty);
    await _tap(tester, _action('import'));
    expect(calls, [pasted]);
    expect(find.text('ความยินยอม: ยังไม่พร้อม'), findsOneWidget);
    expect(find.textContaining('ยืนยันจากภายนอกแล้ว'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets(
    'import serializes rapid taps and disables withdrawal while pending',
    (tester) async {
      final pending = Completer<void>();
      var imports = 0;
      var withdrawals = 0;
      var continuations = 0;
      await _pumpPanel(
        tester,
        permit: _permit(),
        onImport: (_) {
          imports++;
          return pending.future;
        },
        onWithdraw: () async => withdrawals++,
        onContinueLearning: () => continuations++,
      );
      await _enterDocument(tester, _document);
      await tester.ensureVisible(_action('import'));
      await tester.tap(_action('import'));
      await tester.tap(_action('import'));
      await tester.pump();
      expect(imports, 1);
      expect(
        tester.widget<ButtonStyleButton>(_action('withdraw')).onPressed,
        isNull,
      );
      expect(tester.widget<TextField>(_input).enabled, isFalse);
      // Learning navigation is caller owned and does not write research data.
      await _tap(tester, _action('continue'), settle: false);
      expect(continuations, 1);
      expect(withdrawals, 0);
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed import preserves input for explicit bounded retry', (
    tester,
  ) async {
    final calls = <String>[];
    await _pumpPanel(
      tester,
      onImport: (document) async {
        calls.add(document);
        if (calls.length == 1) throw StateError('synthetic_private_signature');
      },
    );
    await _enterDocument(tester, _document);
    await _tap(tester, _action('import'));
    expect(tester.widget<TextField>(_input).controller!.text, _document);
    final status = tester.getSemantics(_status);
    expect(status.flagsCollection.isLiveRegion, isTrue);
    expect(status.label, isNotEmpty);
    expect(status.label.length, lessThanOrEqualTo(240));
    _expectNoPrivateText();
    expect(find.bySemanticsLabel(RegExp('synthetic_private')), findsNothing);
    await _tap(tester, _action('retry'));
    expect(calls, [_document, _document]);
    expect(tester.takeException(), isNull);
  });

  for (final value in ['', ' ', 'not JSON', '[]', 'null', '42']) {
    testWidgets('rejects non-document input ${jsonEncode(value)} locally', (
      tester,
    ) async {
      var calls = 0;
      await _pumpPanel(tester, onImport: (_) async => calls++);
      await _enterDocument(tester, value);
      expect(_action('import'), findsOneWidget);
      await _tap(tester, _action('import'));
      expect(calls, 0);
      expect(find.text('ความยินยอม: ยังไม่พร้อม'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('accepts a JSON document exactly 16 KiB in UTF-8', (
    tester,
  ) async {
    final calls = <String>[];
    await _pumpPanel(tester, onImport: (value) async => calls.add(value));
    final document = '{"value":"${List.filled(16384 - 12, 'a').join()}"}';
    expect(utf8.encode(document), hasLength(16384));
    await _enterDocument(tester, document);
    await _tap(tester, _action('import'));
    expect(calls, [document]);
  });

  testWidgets(
    'rejects a multibyte document above 16 KiB without importing a truncated value',
    (tester) async {
      var calls = 0;
      await _pumpPanel(tester, onImport: (_) async => calls++);
      final document = jsonEncode({'value': List.filled(6000, 'ก').join()});
      expect(document.length, lessThan(16384));
      expect(utf8.encode(document).length, greaterThan(16384));
      await _enterDocument(tester, document);
      await _tap(tester, _action('import'));
      expect(calls, 0);
      expect(_status, findsOneWidget);
      expect(tester.widget<TextField>(_input).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opaque input is obscured and private permit fields never render',
    (tester) async {
      await _pumpPanel(
        tester,
        permit: _permit(
          participantClass: ResearchParticipantClass.minor,
          guardian: true,
          assent: true,
        ),
      );
      await _enterDocument(tester, _document);
      final input = tester.widget<TextField>(_input);
      expect(input.obscureText, isTrue);
      expect(input.readOnly, isTrue);
      expect(input.enableInteractiveSelection, isFalse);
      expect(input.enableSuggestions, isFalse);
      expect(input.autocorrect, isFalse);
      expect(input.autofillHints, isNull);
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      expect(
        editable.renderEditable.text!.toPlainText(),
        isNot(contains('synthetic_private')),
      );
      expect(
        tester.getSemantics(_input).value,
        isNot(contains('synthetic_private')),
      );
      _expectNoPrivateText();
      expect(find.bySemanticsLabel(RegExp('synthetic_private')), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    },
  );

  testWidgets('disposal scrubs retained input after an import failure', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      onImport: (_) async => throw StateError('synthetic_private_error'),
    );
    await _enterDocument(tester, _document);
    await _tap(tester, _action('import'));
    final controller = tester.widget<TextField>(_input).controller!;
    expect(controller.text, _document);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'withdrawal serializes writes and retries only withdrawal on error',
    (tester) async {
      final pending = Completer<void>();
      var withdrawals = 0;
      var imports = 0;
      await _pumpPanel(
        tester,
        permit: _permit(),
        onImport: (_) async => imports++,
        onWithdraw: () {
          withdrawals++;
          return withdrawals == 1 ? pending.future : Future<void>.value();
        },
      );
      await _enterDocument(tester, _document);
      await tester.ensureVisible(_action('withdraw'));
      await tester.tap(_action('withdraw'));
      await tester.tap(_action('withdraw'));
      await tester.pump();
      expect(withdrawals, 1);
      expect(
        tester.widget<ButtonStyleButton>(_action('import')).onPressed,
        isNull,
      );
      pending.completeError(StateError('synthetic_private_error'));
      await tester.pumpAndSettle();
      expect(_status, findsOneWidget);
      _expectNoPrivateText();
      await _tap(tester, _action('retry'));
      expect(withdrawals, 2);
      expect(imports, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final fail in [false, true]) {
    testWidgets(
      'late import ${fail ? 'failure' : 'success'} after disposal is safe',
      (tester) async {
        final pending = Completer<void>();
        await _pumpPanel(tester, onImport: (_) => pending.future);
        await _enterDocument(tester, _document);
        await _tap(tester, _action('import'), settle: false);
        await tester.pumpWidget(const SizedBox.shrink());
        if (fail) {
          pending.completeError(StateError('synthetic_private_error'));
        } else {
          pending.complete();
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'caller removing validated permit clears externally verified status',
    (tester) async {
      await _pumpPanel(tester, permit: _permit(), languageCode: 'en');
      expect(find.text('Consent: Verified externally'), findsOneWidget);
      await _pumpPanel(tester, languageCode: 'en');
      expect(find.text('Consent: Not ready'), findsOneWidget);
      expect(find.textContaining('Verified externally'), findsNothing);
      expect(_action('continue'), findsOneWidget);
    },
  );

  testWidgets(
    'pasting after withdrawal cannot resurrect a stale supplied permit',
    (tester) async {
      var withdrawals = 0;
      await _pumpPanel(
        tester,
        permit: _permit(),
        languageCode: 'en',
        onWithdraw: () async => withdrawals++,
      );
      await _tap(tester, _action('withdraw'));
      expect(find.text('Consent: Not ready'), findsOneWidget);
      await _enterDocument(tester, _document);
      expect(find.text('Consent: Not ready'), findsOneWidget);
      expect(find.textContaining('Verified externally'), findsNothing);
      expect(
        tester.widget<ButtonStyleButton>(_action('withdraw')).onPressed,
        isNull,
      );
      expect(withdrawals, 1);
    },
  );

  for (final language in ['th', 'en']) {
    testWidgets('$language minor panel reflows at 320px and 200 percent text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpPanel(
        tester,
        permit: _permit(participantClass: ResearchParticipantClass.minor),
        languageCode: language,
        textScale: 2,
      );
      expect(find.byType(Scrollable), findsWidgets);
      for (final action in ['continue', 'skip', 'import', 'withdraw']) {
        final finder = _action(action);
        expect(finder, findsOneWidget);
        await tester.ensureVisible(finder);
        expect(finder.hitTestable(), findsOneWidget);
        expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'panel heading, input label and escape actions are keyboard accessible',
    (tester) async {
      await _pumpPanel(tester, permit: _permit(), languageCode: 'en');
      expect(
        tester
            .getSemantics(find.text('Optional research participation'))
            .flagsCollection
            .isHeader,
        isTrue,
      );
      expect(
        find.bySemanticsLabel(RegExp('Externally signed JSON document')),
        findsWidgets,
      );
      final visited = <String>{};
      for (var index = 0; index < 16; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        for (final action in ['continue', 'skip', 'withdraw']) {
          if (tester.getSemantics(_action(action)).flagsCollection.isFocused ==
              Tristate.isTrue) {
            visited.add(action);
          }
        }
      }
      expect(visited, containsAll(['continue', 'skip', 'withdraw']));
    },
  );
}

Finder get _input => find.byType(TextField);
Finder get _status =>
    find.byKey(const ValueKey('research-participation-status'));
Finder _action(String action) =>
    find.byKey(ValueKey('research-participation-$action'));

Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _enterDocument(WidgetTester tester, String document) async {
  expect(_input, findsOneWidget);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => call.method == 'Clipboard.getData'
        ? <String, Object>{'text': document}
        : null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  await _tap(tester, _action('paste'));
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  ResearchParticipationPermit? permit,
  String languageCode = 'th',
  double textScale = 1,
  Future<void> Function(String)? onImport,
  Future<void> Function()? onWithdraw,
  VoidCallback? onContinueLearning,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: ResearchParticipationPanel(
          permit: permit,
          onImport: onImport ?? (_) async {},
          onWithdraw: onWithdraw ?? () async {},
          onContinueLearning: onContinueLearning ?? () {},
          languageCode: languageCode,
        ),
      ),
    ),
  ),
);

void _expectNoPrivateText() {
  // Text finders also inspect EditableText.controller, which intentionally holds
  // opaque input for retry. Inspect visible text and test masked rendering and
  // semantic values separately, never treating controller contents as display.
  final private = RegExp('synthetic_private|StateError|Bad state:');
  expect(
    find.byWidgetPredicate(
      (widget) => switch (widget) {
        Text() => private.hasMatch(
          widget.data ?? widget.textSpan?.toPlainText() ?? '',
        ),
        RichText() => private.hasMatch(widget.text.toPlainText()),
        _ => false,
      },
    ),
    findsNothing,
  );
}

ResearchParticipationPermit _permit({
  ResearchParticipantClass participantClass = ResearchParticipantClass.adult,
  bool guardian = false,
  bool assent = false,
}) => ResearchParticipationPermit(
  id: 'synthetic_private_permit',
  ownerId: 'synthetic_private_owner',
  participantClass: participantClass,
  // Deliberately unsafe display text: render ONLY the enum adult/minor code.
  ageBandCode: 'synthetic_private_dob',
  assignmentId: 'synthetic_private_assignment',
  assignedTreatment: TodayExperiencePresentation.adventure,
  consentReceiptId: 'synthetic_private_consent',
  guardianPermissionReceiptRef: guardian ? 'synthetic_private_guardian' : null,
  learnerAssentReceiptRef: assent ? 'synthetic_private_assent' : null,
  protocolId: 'synthetic_private_protocol',
  protocolVersion: '1',
  issuedAtUtc: DateTime.utc(2026, 1, 1),
  expiresAtUtc: DateTime.utc(2099, 1, 1),
  issuerKeyId: 'synthetic_private_issuer',
  payloadSha256: 'synthetic_private_hash',
  signature: 'synthetic_private_signature',
  localRevision: 1,
  cloudRevision: 1,
  isDeleted: false,
);
