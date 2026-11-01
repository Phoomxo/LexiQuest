import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/content_reports/data/http_content_report_transport.dart';
import 'package:vocab_learning_app/features/content_reports/domain/content_report.dart';
import 'package:vocab_learning_app/features/content_reports/domain/content_report_transport.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';

void main() {
  ContentReportPayload payload() => ContentReportPayload.create(
    reportId: 'content-report:synthetic',
    target: ContentReportTarget.tutorReply(
      text: 'Selected reply only',
      isExcerpt: false,
      replyId: 'synthetic-reply',
      modelVersion: 'synthetic-model',
      generatedAtUtcMs: 1,
    ),
    reason: ReportReason.spelling,
    comment: null,
    queuedAtUtc: DateTime.fromMillisecondsSinceEpoch(2, isUtc: true),
  );

  test('transport default disabled makes no request', () async {
    var requests = 0;
    final binding = ContentReportIdentityBinding(
      ownerId: 'owner',
      firebaseUid: 'synthetic-uid',
      generation: 1,
    );
    final transport = HttpContentReportTransport(
      client: MockClient((_) async {
        requests++;
        return http.Response('', 500);
      }),
      baseUri: Uri.parse('https://synthetic.invalid'),
      identity: ContentReportIdentityPorts(
        currentBinding: () => binding,
        requireCurrent: (_) async {},
        loadIdToken: (_) async => 'synthetic-token',
        dispose: () async {},
      ),
    );
    await expectLater(
      transport.submit(binding, payload()),
      throwsA(
        isA<ContentReportException>().having(
          (error) => error.code,
          'code',
          ContentReportFailureCode.disabled,
        ),
      ),
    );
    expect(requests, 0);
  });

  test('owner ABA during token acquisition rejects before send', () async {
    var requests = 0;
    final before = ContentReportIdentityBinding(
      ownerId: 'owner',
      firebaseUid: 'synthetic-uid',
      generation: 1,
    );
    var current = before;
    final transport = HttpContentReportTransport(
      enabled: true,
      client: MockClient((_) async {
        requests++;
        return http.Response('', 500);
      }),
      baseUri: Uri.parse('https://synthetic.invalid'),
      identity: ContentReportIdentityPorts(
        currentBinding: () => current,
        requireCurrent: (_) async {},
        loadIdToken: (_) async {
          current = ContentReportIdentityBinding(
            ownerId: 'owner',
            firebaseUid: 'synthetic-uid',
            generation: 3,
          );
          return 'synthetic-token';
        },
        dispose: () async {},
      ),
    );
    await expectLater(
      transport.submit(before, payload()),
      throwsA(
        isA<ContentReportException>().having(
          (error) => error.code,
          'code',
          ContentReportFailureCode.ownerChanged,
        ),
      ),
    );
    expect(requests, 0);
  });

  test(
    'POST sends only immutable payload and malformed ACK is not received',
    () async {
      final report = payload();
      final binding = ContentReportIdentityBinding(
        ownerId: 'owner',
        firebaseUid: 'synthetic-uid',
        generation: 1,
      );
      final methods = <String>[];
      final transport = HttpContentReportTransport(
        enabled: true,
        client: MockClient((request) async {
          methods.add(request.method);
          expect(jsonDecode(request.body), {
            'schemaVersion': 1,
            'reportJson': report.reportJson,
            'reportSha256': report.reportSha256,
          });
          expect(request.body, isNot(contains('synthetic-token')));
          expect(request.body, isNot(contains('firebaseUid')));
          return http.Response('{"schemaVersion":1,"receipt":{}}', 200);
        }),
        baseUri: Uri.parse('https://synthetic.invalid'),
        identity: ContentReportIdentityPorts(
          currentBinding: () => binding,
          requireCurrent: (_) async {},
          loadIdToken: (_) async => 'synthetic-token',
          dispose: () async {},
        ),
      );
      await expectLater(
        transport.submit(binding, report),
        throwsA(
          isA<ContentReportException>().having(
            (error) => error.code,
            'code',
            ContentReportFailureCode.invalidResponse,
          ),
        ),
      );
      expect(methods, ['POST']);
    },
  );

  test(
    'valid UID-bound server receipt is accepted and GET only reads original ID',
    () async {
      final report = payload();
      final binding = ContentReportIdentityBinding(
        ownerId: 'owner',
        firebaseUid: 'synthetic-uid',
        generation: 1,
      );
      final key = contentReportDigest(
        jsonEncode([binding.firebaseUid, report.reportId]),
      );
      final body = jsonEncode({
        'schemaVersion': 1,
        'receipt': {
          'reportId': report.reportId,
          'reportSha256': report.reportSha256,
          'receiptId': 'content-report-receipt:$key',
          'receivedAtUtc': '2026-11-01T00:00:00.000Z',
        },
        'moderation': {
          'revision': 1,
          'status': 'received',
          'decisionId': null,
          'publicNote': null,
          'decidedAtUtc': null,
        },
      });
      final methods = <String>[];
      final transport = HttpContentReportTransport(
        enabled: true,
        client: MockClient((request) async {
          methods.add(request.method);
          expect(request.followRedirects, isFalse);
          if (request.method == 'GET') {
            expect(request.url.queryParameters, {'reportId': report.reportId});
            expect(request.body, isEmpty);
          }
          return http.Response(body, 200);
        }),
        baseUri: Uri.parse('https://synthetic.invalid'),
        identity: ContentReportIdentityPorts(
          currentBinding: () => binding,
          requireCurrent: (_) async {},
          loadIdToken: (_) async => 'synthetic-token',
          dispose: () async {},
        ),
      );
      final ack = await transport.submit(binding, report);
      expect(ack.receipt.reportSha256, report.reportSha256);
      expect(ack.moderation.status, ContentReportModerationStatus.received);
      await transport.readReceipt(binding, report);
      expect(methods, ['POST', 'GET']);
    },
  );

  test('oversized response is rejected without recording a receipt', () async {
    final binding = ContentReportIdentityBinding(
      ownerId: 'owner',
      firebaseUid: 'synthetic-uid',
      generation: 1,
    );
    final transport = HttpContentReportTransport(
      enabled: true,
      client: MockClient((_) async => http.Response('x' * 16385, 200)),
      baseUri: Uri.parse('https://synthetic.invalid'),
      identity: ContentReportIdentityPorts(
        currentBinding: () => binding,
        requireCurrent: (_) async {},
        loadIdToken: (_) async => 'synthetic-token',
        dispose: () async {},
      ),
    );
    await expectLater(
      transport.submit(binding, payload()),
      throwsA(
        isA<ContentReportException>().having(
          (e) => e.code,
          'code',
          ContentReportFailureCode.invalidResponse,
        ),
      ),
    );
  });

  test(
    'token timeout cannot issue a late POST after the caller has failed',
    () async {
      final binding = ContentReportIdentityBinding(
        ownerId: 'owner',
        firebaseUid: 'synthetic-uid',
        generation: 1,
      );
      final token = Completer<String?>();
      var requests = 0;
      final transport = HttpContentReportTransport(
        enabled: true,
        timeout: const Duration(milliseconds: 5),
        client: MockClient((_) async {
          requests++;
          return http.Response('', 500);
        }),
        baseUri: Uri.parse('https://synthetic.invalid'),
        identity: ContentReportIdentityPorts(
          currentBinding: () => binding,
          requireCurrent: (_) async {},
          loadIdToken: (_) => token.future,
          dispose: () async {},
        ),
      );
      await expectLater(
        transport.submit(binding, payload()),
        throwsA(isA<ContentReportException>()),
      );
      token.complete('synthetic-token');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(requests, 0);
    },
  );

  test(
    'owner change queued after final async validation prevents the POST itself',
    () async {
      final original = ContentReportIdentityBinding(
        ownerId: 'owner',
        firebaseUid: 'synthetic-uid',
        generation: 1,
      );
      var current = original;
      var persistentProbes = 0;
      var armed = false;
      var requests = 0;
      final transport = HttpContentReportTransport(
        enabled: true,
        client: MockClient((_) async {
          requests++;
          return http.Response('', 500);
        }),
        baseUri: Uri.parse('https://synthetic.invalid'),
        identity: ContentReportIdentityPorts(
          currentBinding: () {
            final observed = current;
            if (persistentProbes >= 3 && !armed) {
              armed = true;
              scheduleMicrotask(
                () => current = ContentReportIdentityBinding(
                  ownerId: 'owner',
                  firebaseUid: 'synthetic-uid',
                  generation: 3,
                ),
              );
            }
            return observed;
          },
          requireCurrent: (_) async {
            persistentProbes++;
          },
          loadIdToken: (_) async => 'synthetic-token',
          dispose: () async {},
        ),
      );
      await expectLater(
        transport.submit(original, payload()),
        throwsA(
          isA<ContentReportException>().having(
            (error) => error.code,
            'code',
            ContentReportFailureCode.ownerChanged,
          ),
        ),
      );
      expect(requests, 0);
    },
  );

  test(
    'owner change after send invocation prevents emission of report body bytes',
    () async {
      final original = ContentReportIdentityBinding(
        ownerId: 'owner',
        firebaseUid: 'synthetic-uid',
        generation: 1,
      );
      var current = original;
      var emittedBytes = 0;
      final transport = HttpContentReportTransport(
        enabled: true,
        client: MockClient.streaming((request, body) async {
          current = ContentReportIdentityBinding(
            ownerId: 'owner',
            firebaseUid: 'synthetic-uid',
            generation: 2,
          );
          await for (final chunk in body) {
            emittedBytes += chunk.length;
          }
          return http.StreamedResponse(const Stream<List<int>>.empty(), 500);
        }),
        baseUri: Uri.parse('https://synthetic.invalid'),
        identity: ContentReportIdentityPorts(
          currentBinding: () => current,
          requireCurrent: (_) async {},
          loadIdToken: (_) async => 'synthetic-token',
          dispose: () async {},
        ),
      );
      await expectLater(
        transport.submit(original, payload()),
        throwsA(
          isA<ContentReportException>().having(
            (error) => error.code,
            'code',
            ContentReportFailureCode.ownerChanged,
          ),
        ),
      );
      expect(emittedBytes, 0);
    },
  );
}
