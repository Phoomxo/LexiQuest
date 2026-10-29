import 'package:crypto/crypto.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_authority.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_authority.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_instrument_catalog.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';

import 'assessment_authority_harness.dart';

export 'assessment_authority_harness.dart';

final class AssessmentWriterFixture {
  AssessmentWriterFixture(this.authorities);
  final AssessmentAuthorityFixture authorities;
  late final WriterContentAuthority content;
  late final AssessmentInstrumentDefinition definition;
  late final DriftAssessmentRepository repository;
  late String cycleId;

  static Future<AssessmentWriterFixture> open() async {
    final authorities = await AssessmentAuthorityFixture.open();
    final result = AssessmentWriterFixture(authorities);
    final baseline = await authorities.study.baseline();
    result.cycleId = baseline.run!.id;
    result.definition = _withAliases(authorities.definition);
    result.content = WriterContentAuthority(authorities, result.definition);
    final mapping = authorities.mapping;
    final authority = DriftAssessmentAuthority(
      cache: authorities.cache,
      mapping: AssessmentAuthorityMapping(
        protocolId: mapping.protocolId,
        protocolVersion: mapping.protocolVersion,
        protocolRevision: mapping.protocolRevision,
        instrumentId: mapping.instrumentId,
        instrumentVersion: mapping.instrumentVersion,
        instrumentRevision: mapping.instrumentRevision,
        formId: mapping.formId,
        formVersion: mapping.formVersion,
        formContentRevision: mapping.formContentRevision,
        instrumentChecksumSha256: mapping.instrumentChecksumSha256,
        formChecksumSha256: result.definition.formChecksumSha256,
        experimentId: mapping.experimentId,
        experimentVersion: mapping.experimentVersion,
        contentRevision: mapping.contentRevision,
      ),
    );
    result.repository = DriftAssessmentRepository(
      authorities.study.database,
      authority: authority,
      cycleReader: authorities.cycleReader(),
      catalog: AssessmentInstrumentCatalog(entries: [result.definition]),
      contentAuthority: result.content,
      buildInfo: authorities.study.runtime.context.buildInfo,
      participationPermitId: 'synthetic-participation',
    );
    if (!await authorities.cache.refresh()) {
      throw StateError('Synthetic Assessment refresh failed.');
    }
    return result;
  }

  AssessmentStartCommand command({
    AssessmentPhase phase = AssessmentPhase.pre,
    String? runId,
    String? sessionId,
  }) => AssessmentStartCommand(
    runId: runId ?? 'synthetic-writer-${phase.name}',
    learningSessionId: sessionId ?? 'synthetic-writer-session-${phase.name}',
    studyCycleId: cycleId,
    phase: phase,
    instrumentId: authorities.definition.instrumentId,
    instrumentVersion: authorities.definition.instrumentVersion,
    formId: authorities.definition.formId,
    formVersion: authorities.definition.formVersion,
  );

  Future<AssessmentRun> start({AssessmentPhase phase = AssessmentPhase.pre}) =>
      repository.start(
        command(phase: phase),
        ownerId: 'owner-a',
        stillVisible: () => true,
      );

  Future<void> close() => authorities.close();

  Future<Map<String, List<Map<String, Object?>>>> ordinaryRows() async => {
    for (final table in authorities.study.database.allTables)
      if (!{
        'assessment_runs',
        'learning_sessions',
        'answer_attempts',
      }.contains(table.actualTableName))
        table.actualTableName: await authorities.study.rows(
          table.actualTableName,
        ),
  };
}

final class WriterContentAuthority implements AssessmentFormContentAuthority {
  WriterContentAuthority(this.authorities, this.definition);
  final AssessmentAuthorityFixture authorities;
  final AssessmentInstrumentDefinition definition;
  int calls = 0;
  bool fail = false;
  Future<void> Function()? onRead;
  final transactionReads = <bool>[];

  @override
  Future<AssessmentVerifiedFormContent> requireVerified(
    AssessmentFormContentIdentity identity,
  ) async {
    calls++;
    transactionReads.add(
      await authorities.cache.ownerWrites.hasAmbientTransaction(),
    );
    await onRead?.call();
    if (fail) throw StateError('Synthetic content unavailable.');
    return AssessmentVerifiedFormContent(
      identity: identity,
      checksumSha256: definition.formChecksumSha256,
      bytes: definition.formBytes,
    );
  }
}

AssessmentInstrumentDefinition _withAliases(
  AssessmentInstrumentDefinition source,
) {
  final original = source.items.single;
  final items = [
    AssessmentItemDefinition(
      itemId: original.itemId,
      prompt: original.prompt,
      wordId: original.wordId,
      promptMode: original.promptMode,
      scoringRuleVersion: original.scoringRuleVersion,
      responses: {
        ...original.responses,
        'synthetic yes alias': const AssessmentControlledResponse(
          responseCode: 'correct',
          isCorrect: true,
        ),
        'synthetic no alias': const AssessmentControlledResponse(
          responseCode: 'incorrect',
          isCorrect: false,
        ),
        'synthetic different no': const AssessmentControlledResponse(
          responseCode: 'other-wrong',
          isCorrect: false,
        ),
      },
    ),
  ];
  final bytes = AssessmentInstrumentDefinition.canonicalFormBytes(
    instrumentId: source.instrumentId,
    instrumentVersion: source.instrumentVersion,
    formId: source.formId,
    formVersion: source.formVersion,
    formContentRevision: source.formContentRevision,
    items: items,
  );
  return AssessmentInstrumentDefinition(
    instrumentId: source.instrumentId,
    instrumentVersion: source.instrumentVersion,
    formId: source.formId,
    formVersion: source.formVersion,
    formContentRevision: source.formContentRevision,
    sourceState: source.sourceState,
    reviewState: source.reviewState,
    protocolId: source.protocolId,
    experimentId: source.experimentId,
    experimentVersion: source.experimentVersion,
    contentRevision: source.contentRevision,
    instrumentBytes: source.instrumentBytes,
    formBytes: bytes,
    instrumentChecksumSha256: source.instrumentChecksumSha256,
    formChecksumSha256: sha256.convert(bytes).toString(),
    items: items,
  );
}
