import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../identity/domain/local_owner_repository.dart';
import '../../research/domain/research_operation_authorizer.dart';
import '../../consent/application/research_consent_use_cases.dart';
import '../../consent/domain/research_consent.dart';
import '../../rewards/domain/reward_ledger.dart';
import '../data/drift_export_reader.dart';
import '../domain/export_contracts.dart';

typedef ExportUtcNow = DateTime Function();
typedef ExportFontLoader = Future<ByteData> Function();

final class ExportUseCases {
  const ExportUseCases({
    required this.owners,
    required this.reader,
    required this.store,
    required this.nowUtc,
    required this.loadThaiFont,
    required this.researchConsent,
    this.researchAuthorizer = const DenyAllResearchOperationAuthorizer(),
  });

  final LocalOwnerRepository owners;
  final ExportReader reader;
  final ExportArtifactStore store;
  final ExportUtcNow nowUtc;
  final ExportFontLoader loadThaiFont;
  final ResearchConsentUseCases researchConsent;
  final ResearchOperationAuthorizer researchAuthorizer;

  Future<ExportArtifact> prepare({
    required ExportFormat format,
    required ExportSelection selection,
    required ExportCancellation cancellation,
  }) async => (await _prepare(
    format: format,
    selection: selection,
    cancellation: cancellation,
  )).artifact;

  Future<({ExportArtifact artifact, String ownerId})> _prepare({
    required ExportFormat format,
    required ExportSelection selection,
    required ExportCancellation cancellation,
  }) async {
    if (selection.isEmpty) {
      throw const ExportException(ExportFailureCode.noSelection);
    }
    if (selection.includeRewards &&
        (format == ExportFormat.researchJson || format == ExportFormat.anki)) {
      throw const ExportException(ExportFailureCode.unavailable);
    }
    cancellation.throwIfCancelled();
    late final String ownerId;
    if (format == ExportFormat.researchJson) {
      final consent = await _loadResearchConsent();
      cancellation.throwIfCancelled();
      if (!consent.accepted) {
        throw const ExportException(ExportFailureCode.consentRequired);
      }
      ownerId = consent.ownerId;
      await _requireResearchAuthorization(ownerId, cancellation);
    } else {
      ownerId = await _loadActiveOwnerId();
    }
    cancellation.throwIfCancelled();
    final data = await _loadData(
      ownerId: ownerId,
      vocabulary: selection.includeVocabulary,
      attempts: selection.includeAttempts,
      reading: selection.includeReading,
      rewards: selection.includeRewards,
    );
    cancellation.throwIfCancelled();
    await _requireCurrentScope(ownerId, format, cancellation);
    if (data.recordCount == 0) {
      throw const ExportException(ExportFailureCode.noData);
    }
    final generatedAt = _now();
    final bytes = switch (format) {
      ExportFormat.csv => _csv(data, generatedAt),
      ExportFormat.anki => _anki(data),
      ExportFormat.researchJson => _researchJson(data, generatedAt),
      ExportFormat.pdf => await _pdf(data, generatedAt, cancellation),
    };
    cancellation.throwIfCancelled();
    await _requireCurrentScope(ownerId, format, cancellation);
    final artifact = ExportArtifact(
      format: format,
      suggestedFileName: _fileName(format, generatedAt),
      mimeType: switch (format) {
        ExportFormat.csv => 'text/csv',
        ExportFormat.anki => 'text/tab-separated-values',
        ExportFormat.researchJson => 'application/json',
        ExportFormat.pdf => 'application/pdf',
      },
      bytes: bytes,
      recordCount: data.recordCount,
      schemaVersion: data.rewards == null ? 1 : 2,
      algorithmVersion: 1,
      generatedAtUtc: generatedAt,
      timeZone: 'UTC',
      exclusions: const [
        'Gemini API key',
        'Firebase authentication token',
        'direct personal identifiers',
        'raw microphone audio',
      ],
    );
    return (artifact: artifact, ownerId: ownerId);
  }

  Future<ExportSaveResult> export({
    required ExportFormat format,
    required ExportSelection selection,
    required ExportCancellation cancellation,
  }) async {
    final prepared = await _prepare(
      format: format,
      selection: selection,
      cancellation: cancellation,
    );
    cancellation.throwIfCancelled();
    return store.save(
      prepared.artifact,
      cancellation: cancellation,
      revalidateBeforeWrite: () => _requireCurrentScope(
        prepared.ownerId,
        prepared.artifact.format,
        cancellation,
      ),
    );
  }

  Future<void> _requireCurrentScope(
    String ownerId,
    ExportFormat format,
    ExportCancellation cancellation,
  ) async {
    cancellation.throwIfCancelled();
    if (format == ExportFormat.researchJson) {
      final consent = await _loadResearchConsent();
      cancellation.throwIfCancelled();
      if (consent.ownerId != ownerId) {
        throw const ExportException(ExportFailureCode.cancelled);
      }
      if (!consent.accepted) {
        throw const ExportException(ExportFailureCode.consentRequired);
      }
      await _requireResearchAuthorization(ownerId, cancellation);
    } else if (await _loadActiveOwnerId() != ownerId) {
      throw const ExportException(ExportFailureCode.cancelled);
    }
    cancellation.throwIfCancelled();
  }

  Future<ResearchConsentStatus> _loadResearchConsent() async {
    try {
      return await researchConsent.load();
    } on ExportException {
      rethrow;
    } catch (error) {
      if (error is StateError &&
          error.message ==
              'active owner changed while loading research consent') {
        throw ExportException(ExportFailureCode.cancelled, error);
      }
      throw ExportException(ExportFailureCode.unavailable, error);
    }
  }

  Future<void> _requireResearchAuthorization(
    String ownerId,
    ExportCancellation cancellation,
  ) async {
    cancellation.throwIfCancelled();
    try {
      if (!await researchAuthorizer.authorize(
        ownerId: ownerId,
        operation: ResearchOperation.export,
      )) {
        throw const ExportException(ExportFailureCode.unavailable);
      }
    } on ExportException {
      rethrow;
    } catch (_) {
      throw const ExportException(ExportFailureCode.unavailable);
    }
    cancellation.throwIfCancelled();
  }

  Future<String> _loadActiveOwnerId() async {
    try {
      return (await owners.getOrCreateActiveOwner()).id;
    } on ExportException {
      rethrow;
    } catch (error) {
      throw ExportException(ExportFailureCode.unavailable, error);
    }
  }

  Future<ExportDataSet> _loadData({
    required String ownerId,
    required bool vocabulary,
    required bool attempts,
    required bool reading,
    required bool rewards,
  }) async {
    try {
      return await reader.load(
        ownerId: ownerId,
        vocabulary: vocabulary,
        attempts: attempts,
        reading: reading,
        rewards: rewards,
      );
    } on ExportException {
      rethrow;
    } catch (error) {
      throw ExportException(ExportFailureCode.unavailable, error);
    }
  }

  Uint8List _csv(ExportDataSet data, DateTime generatedAt) {
    final out = StringBuffer()
      ..writeln(
        '# LexiQuest export schema=${data.rewards == null ? 1 : 2} algorithm=1 timezone=UTC',
      )
      ..writeln('# generated_at=${generatedAt.toIso8601String()}')
      ..writeln('# sample_size=${data.recordCount}')
      ..write(
        data.rewards == null ? '' : '# coin_balance=${data.rewards!.balance}\n',
      )
      ..writeln(
        'record_type,evidence_id,subject,prompt_mode,is_correct,response_time_ms,occurred_at_utc,detail',
      );
    for (final row in data.vocabulary) {
      out.writeln(
        _csvRow([
          'vocabulary',
          row.id,
          row.spelling,
          '',
          '',
          '',
          '',
          '${row.category}|${row.meaning}|${row.partOfSpeech}|${row.cefrLevel ?? ''}|${row.source}',
        ]),
      );
    }
    for (final row in data.attempts) {
      out.writeln(
        _csvRow([
          'attempt',
          row.id,
          row.spelling,
          row.promptMode,
          row.isCorrect ? '1' : '0',
          row.responseTimeMs?.toString() ?? '',
          row.occurredAtUtc.toIso8601String(),
          row.providerProvenance ?? '',
        ]),
      );
    }
    for (final row in data.reading) {
      out.writeln(
        _csvRow([
          'reading',
          '${row.documentId}@${row.documentRevision}',
          row.documentId,
          '',
          row.isCompleted ? '1' : '0',
          '',
          row.updatedAtUtc.toIso8601String(),
          'position=${row.lastPosition}',
        ]),
      );
    }
    for (final effect
        in data.rewards?.effects ?? const <RewardLedgerEffect>[]) {
      final entry = effect.entry;
      out.writeln(
        _csvRow([
          'reward',
          entry.id,
          entry.itemId ?? entry.type,
          '',
          '',
          '',
          DateTime.fromMillisecondsSinceEpoch(
            entry.occurredAtUtcMs,
            isUtc: true,
          ).toIso8601String(),
          jsonEncode(_rewardAuditDetails(effect)),
        ]),
      );
    }
    return Uint8List.fromList(utf8.encode('\uFEFF$out'));
  }

  Uint8List _anki(ExportDataSet data) {
    if (data.vocabulary.isEmpty) {
      throw const ExportException(ExportFailureCode.noData);
    }
    final out = StringBuffer()
      ..writeln('#separator:tab')
      ..writeln('#html:false')
      ..writeln('#notetype:Basic')
      ..writeln('#deck:LexiQuest');
    for (final row in data.vocabulary) {
      out.writeln(
        '${_tab(row.spelling)}\t${_tab(row.meaning)}'
        '\t${_tab(row.category)}\t${_tab(row.id)}',
      );
    }
    return Uint8List.fromList(utf8.encode(out.toString()));
  }

  Uint8List _researchJson(ExportDataSet data, DateTime generatedAt) {
    final payload = <String, Object?>{
      'schemaVersion': 1,
      'algorithmVersion': 1,
      'generatedAtUtc': generatedAt.toIso8601String(),
      'timeZone': 'UTC',
      'sampleSize': data.recordCount,
      'exclusions': const [
        'secrets',
        'direct personal identifiers',
        'raw audio',
      ],
      'vocabulary': [
        for (final row in data.vocabulary)
          {
            'evidenceId': row.id,
            'category': row.category,
            'spelling': row.spelling,
            'meaning': row.meaning,
            'partOfSpeech': row.partOfSpeech,
            'cefrLevel': row.cefrLevel,
            'source': row.source,
          },
      ],
      'attempts': [
        for (final row in data.attempts)
          {
            'evidenceId': row.id,
            'sessionId': row.sessionId,
            'wordId': row.wordId,
            'spelling': row.spelling,
            'promptMode': row.promptMode,
            'isCorrect': row.isCorrect,
            'responseTimeMs': row.responseTimeMs,
            'occurredAtUtc': row.occurredAtUtc.toIso8601String(),
            'providerProvenance': row.providerProvenance,
          },
      ],
      'reading': [
        for (final row in data.reading)
          {
            'documentId': row.documentId,
            'documentRevision': row.documentRevision,
            'lastPosition': row.lastPosition,
            'isCompleted': row.isCompleted,
            'updatedAtUtc': row.updatedAtUtc.toIso8601String(),
          },
      ],
    };
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );
  }

  Future<Uint8List> _pdf(
    ExportDataSet data,
    DateTime generatedAt,
    ExportCancellation cancellation,
  ) async {
    late final ByteData fontData;
    try {
      fontData = await loadThaiFont();
    } on ExportException {
      rethrow;
    } catch (error) {
      throw ExportException(ExportFailureCode.unavailable, error);
    }
    cancellation.throwIfCancelled();
    final font = pw.Font.ttf(fontData);
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (_) => [
          pw.Header(level: 0, text: 'LexiQuest รายงานข้อมูลการเรียน'),
          pw.Text('สร้างเมื่อ: ${generatedAt.toIso8601String()}'),
          pw.Text('เขตเวลา: UTC'),
          pw.Text('Schema v${data.rewards == null ? 1 : 2} · Algorithm v1'),
          pw.Text('จำนวนข้อมูลทั้งหมด: ${data.recordCount}'),
          pw.SizedBox(height: 12),
          pw.Header(level: 1, text: 'คำศัพท์ (${data.vocabulary.length})'),
          if (data.vocabulary.isEmpty)
            pw.Text('ไม่มีข้อมูลคำศัพท์ที่เลือก')
          else
            for (final row in data.vocabulary)
              pw.Text('${row.spelling} — ${row.meaning} (${row.category})'),
          pw.Header(level: 1, text: 'คำตอบ (${data.attempts.length})'),
          if (data.attempts.isEmpty)
            pw.Text('ไม่มีข้อมูลคำตอบที่เลือก')
          else
            for (final row in data.attempts)
              pw.Text(
                '${row.occurredAtUtc.toIso8601String()} · ${row.spelling} · '
                '${row.isCorrect ? 'ถูก' : 'ผิด'} · '
                '${row.responseTimeMs ?? '-'} ms',
              ),
          pw.Header(level: 1, text: 'การอ่าน (${data.reading.length})'),
          if (data.reading.isEmpty)
            pw.Text('ไม่มีข้อมูลการอ่านที่เลือก')
          else
            for (final row in data.reading)
              pw.Text(
                '${row.documentId}@${row.documentRevision} · '
                'ตำแหน่ง ${row.lastPosition} · '
                '${row.isCompleted ? 'อ่านจบ' : 'กำลังอ่าน'}',
              ),
          if (data.rewards != null) ...[
            pw.Header(level: 1, text: 'Coins (${data.rewards!.balance})'),
            for (final effect in data.rewards!.effects)
              pw.Text(jsonEncode(_rewardAuditDetails(effect))),
          ],
          pw.SizedBox(height: 12),
          pw.Text(
            'ไม่รวม: API key, token ยืนยันตัวตน, ข้อมูลระบุตัวบุคคลโดยตรง และเสียงดิบ',
          ),
        ],
      ),
    );
    return document.save();
  }

  Map<String, Object?> _rewardAuditDetails(RewardLedgerEffect effect) => {
    'evidenceId': effect.entry.id,
    'transactionType': effect.entry.type,
    'itemId': effect.entry.itemId,
    'occurredAtUtcMs': effect.entry.occurredAtUtcMs,
    'rawAmount': effect.entry.amount,
    'effectiveAmount': effect.effectiveAmount,
    'status': effect.status.name,
    'localOnly': effect.entry.localOnly,
    'sourceEventId': effect.entry.sourceEventId,
  };

  String _csvRow(List<String> cells) => cells
      .map((cell) => _spreadsheetSafe(cell))
      .map((cell) => '"${cell.replaceAll('"', '""')}"')
      .join(',');

  String _tab(String value) => _spreadsheetSafe(
    value.replaceAll('\t', ' ').replaceAll('\r', ' ').replaceAll('\n', ' '),
  );

  String _spreadsheetSafe(String value) {
    if (value.isNotEmpty && const {'=', '+', '-', '@'}.contains(value[0])) {
      return "'$value";
    }
    return value;
  }

  String _fileName(ExportFormat format, DateTime generatedAt) {
    final stamp = generatedAt
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .split('.')
        .first;
    final extension = switch (format) {
      ExportFormat.csv => 'csv',
      ExportFormat.anki => 'txt',
      ExportFormat.researchJson => 'json',
      ExportFormat.pdf => 'pdf',
    };
    return 'lexiquest-$stamp.$extension';
  }

  DateTime _now() {
    final value = nowUtc();
    if (!value.isUtc) {
      throw ArgumentError.value(value, 'nowUtc', 'must be UTC');
    }
    return value;
  }
}
