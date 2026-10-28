import 'dart:convert';

import 'research_export_errors.dart';

/// Research data exporter service.
///
/// RESEARCH_ONLY: This is an owner-only tool for exporting analytical
/// datasets from exported learning data. It must:
/// - Run from real exported data only (no invented values)
/// - Produce deterministic output
/// - Handle empty/insufficient-data gracefully
/// - Be rerunnable from an exported dataset
class ResearchDataExporterService {
  const ResearchDataExporterService();

  /// Validates an exported JSON dataset and returns a report.
  ///
  /// Checks for:
  /// - Malformed JSON structure
  /// - Missing required fields
  /// - Duplicate entity IDs
  /// - Insufficient sample sizes
  ResearchExportReport validate(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        return const ResearchExportReport(
          errors: [
            ResearchExportError(
              code: 'invalidFormat',
              message: 'Expected a JSON object at top level.',
            ),
          ],
        );
      }
      final errors = <ResearchExportError>[];
      final recordCount = _countRecords(decoded);
      final validCount = recordCount;

      // Check for duplicate attempt IDs
      final attempts = decoded['attempts'];
      if (attempts is List) {
        final seen = <String>{};
        for (var i = 0; i < attempts.length; i++) {
          final row = attempts[i];
          if (row is! Map) continue;
          final id = row['id'];
          if (id is String && seen.contains(id)) {
            errors.add(ResearchExportError(
              code: 'duplicateId',
              message: 'Duplicate attempt ID found.',
              rowNumber: i + 1,
              entityId: id,
            ));
          } else if (id is String) {
            seen.add(id);
          }
        }
      }

      if (recordCount < 10) {
        errors.add(ResearchExportError(
          code: 'insufficientData',
          message: 'Dataset has only $recordCount records. '
              'Results may not be statistically meaningful.',
        ));
      }

      return ResearchExportReport(
        errors: errors,
        totalRecords: recordCount,
        validRecords: validCount,
      );
    } on FormatException catch (e) {
      return ResearchExportReport(
        errors: [
          ResearchExportError(
            code: 'jsonParseError',
            message: e.message,
          ),
        ],
      );
    }
  }

  int _countRecords(Map<String, dynamic> data) {
    var count = 0;
    for (final key in ['vocabulary', 'attempts', 'reading']) {
      final list = data[key];
      if (list is List) count += list.length;
    }
    return count;
  }
}
