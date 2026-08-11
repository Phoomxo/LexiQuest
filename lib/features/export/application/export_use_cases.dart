import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../consent/application/research_consent_use_cases.dart';
import '../data/drift_export_reader.dart';
import '../domain/export_contracts.dart';

typedef ExportUtcNow = DateTime Function();
typedef ExportFontLoader = Future<ByteData> Function();

final class ExportUseCases {
  const ExportUseCases({
    required this.reader,
    required this.store,
    required this.nowUtc,
    required this.loadThaiFont,
  });

  final DriftExportReader reader;
  final ExportArtifactStore store;
  final ExportUtcNow nowUtc;
  final ExportFontLoader loadThaiFont;

  Future<ExportArtifact> prepare({
    required ExportFormat format,
    required ExportSelection selection,
    required ExportCancellation cancellation,
  }) async {
    if (selection.isEmpty) {
      throw const ExportException(ExportFailureCode.noSelection);
    }
    cancellation.throwIfCancelled();
    final data = await reader.loadActiveSnapshot(
      vocabulary: selection.includeVocabulary,
      attempts: selection.includeAttempts,
      reading: selection.includeReading,
      researchConsentVersion: format == ExportFormat.researchJson
          ? ResearchConsentUseCases.currentVersion
          : null,
    );
    cancellation.throwIfCancelled();
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
    final sha256 = crypto.sha256.convert(bytes).toString();
    final integrityReport = _buildIntegrityReport(data);
    return ExportArtifact(
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
      schemaVersion: 1,
      algorithmVersion: 1,
      generatedAtUtc: generatedAt,
      timeZone: 'UTC',
      sha256: sha256,
      integrityReport: integrityReport,
      exclusions: const [
        'Gemini API key',
        'Firebase authentication token',
        'direct personal identifiers',
        'raw microphone audio',
      ],
    );
  }

  Future<ExportSaveResult> export({
    required ExportFormat format,
    required ExportSelection selection,
    required ExportCancellation cancellation,
  }) async {
    final artifact = await prepare(
      format: format,
      selection: selection,
      cancellation: cancellation,
    );
    cancellation.throwIfCancelled();
    return store.save(artifact, cancellation: cancellation);
  }

  Uint8List _csv(ExportDataSet data, DateTime generatedAt) {
    final out = StringBuffer()
      ..writeln('# LexiQuest export schema=1 algorithm=1 timezone=UTC')
      ..writeln('# generated_at=${generatedAt.toIso8601String()}')
      ..writeln('# sample_size=${data.recordCount}')
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
    final fontData = await loadThaiFont();
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
          pw.Text('Schema v1 · Algorithm v1'),
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
          pw.SizedBox(height: 12),
          pw.Text(
            'ไม่รวม: API key, token ยืนยันตัวตน, ข้อมูลระบุตัวบุคคลโดยตรง และเสียงดิบ',
          ),
        ],
      ),
    );
    return document.save();
  }

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

  /// Builds an integrity report detecting duplicate attempt IDs and
  /// flagging insufficient sample sizes.
  ExportIntegrityReport _buildIntegrityReport(ExportDataSet data) {
    final allIds = <String>[];
    allIds.addAll(data.attempts.map((a) => a.id));

    final seen = <String>{};
    final duplicates = <String>[];
    for (final id in allIds) {
      if (seen.contains(id)) {
        duplicates.add(id);
      } else {
        seen.add(id);
      }
    }

    final total = data.recordCount;
    final isInsufficient = total < 10;

    return ExportIntegrityReport(
      duplicateEventIds: duplicates,
      totalRecords: total,
      isInsufficient: isInsufficient,
    );
  }
}
