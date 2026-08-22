import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _canonicalStreakAuthority =
    'lib/features/motivation/data/drift_streak_repository.dart';
const _ownerLifecycleMigration =
    'lib/features/identity/data/drift_owner_upgrade_repository.dart';
const _approvedStreakWriters = <String>{_canonicalStreakAuthority};

const _mutationTargetArgument = <String, int>{
  'into': 0,
  'update': 0,
  'delete': 0,
  'insert': 0,
  'insertAll': 0,
  'insertAllOnConflictUpdate': 0,
  'replace': 0,
  'replaceAll': 0,
  'deleteWhere': 0,
  'deleteAll': 0,
  'insertFromSelect': 0,
};

final _mutationCallPattern = RegExp(
  '\\b(${(_mutationTargetArgument.keys.toList(growable: false)..sort((left, right) => right.length.compareTo(left.length))).map(RegExp.escape).join('|')})\\s*\\(',
  multiLine: true,
);
final _streakCompanionPattern = RegExp(
  r'\bStreakStatesCompanion(?:\s*\.\s*insert)?\s*\(',
  multiLine: true,
);
final _lineageAssignmentPattern = RegExp(
  r'\b([A-Za-z_$][A-Za-z0-9_$]*)\s*=(?!=|>)',
  multiLine: true,
);
final _rawStreakMutationPattern = RegExp(
  r'\b(?:INSERT(?:\s+OR\s+(?:ROLLBACK|ABORT|FAIL|IGNORE|REPLACE))?\s+INTO|'
  r'REPLACE\s+INTO|'
  r'UPDATE(?:\s+OR\s+(?:ROLLBACK|ABORT|FAIL|IGNORE|REPLACE))?|'
  r'DELETE\s+FROM)'
  r'\s+["`]?streak_states\b',
  caseSensitive: false,
  multiLine: true,
);

const _tableReceiverMutationMethods = <String>{
  'insert',
  'insertOne',
  'insertAll',
  'insertOnConflictUpdate',
  'insertReturning',
  'insertReturningOrNull',
  'update',
  'replaceOne',
  'delete',
  'deleteOne',
  'deleteWhere',
  'deleteAll',
};
const _managerReceiverMutationMethods = <String>{
  'create',
  'createReturning',
  'createReturningOrNull',
  'bulkCreate',
  'replace',
  'bulkReplace',
  'update',
  'delete',
};
const _tableProducerMethods = <String>{'createAlias'};
const _managerCompositionMethods = <String>{
  'filter',
  'withReferences',
  'withFields',
  'orderBy',
  'limit',
};

final _receiverMutationPattern = RegExp(
  '\\.\\s*(${({..._tableReceiverMutationMethods, ..._managerReceiverMutationMethods}.toList(growable: false)..sort((left, right) => right.length.compareTo(left.length))).map(RegExp.escape).join('|')})\\s*\\(',
  multiLine: true,
);

class _DetectedStreakWrite {
  const _DetectedStreakWrite({
    required this.path,
    required this.matchedText,
    required this.offset,
  });

  final String path;
  final String matchedText;
  final int offset;
}

class _SourceRange {
  const _SourceRange(this.start, this.end);

  final int start;
  final int end;

  bool contains(int offset) => offset >= start && offset < end;
}

class _StreakAliases {
  const _StreakAliases({required this.tables, required this.managers});

  final Set<String> tables;
  final Set<String> managers;
}

class _DetectorCase {
  const _DetectorCase(this.name, this.source);

  final String name;
  final String source;
}

Map<String, String> _productionDartSources() {
  final entries =
      Directory('lib')
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map(
            (file) => MapEntry(
              file.path.replaceAll(Platform.pathSeparator, '/'),
              file.readAsStringSync(),
            ),
          )
          .where(
            (entry) =>
                entry.key != 'lib/data/local/app_database.g.dart' &&
                !entry.key.startsWith('lib/data/local/tables/'),
          )
          .toList(growable: false)
        ..sort((left, right) => left.key.compareTo(right.key));
  return Map<String, String>.fromEntries(entries);
}

List<_DetectedStreakWrite> _detectStreakWrites(Map<String, String> sources) {
  final writes = <_DetectedStreakWrite>[];
  for (final entry in sources.entries) {
    final source = entry.value;
    final code = _maskDartCommentsAndStrings(source);
    final aliases = _resolveStreakAliases(code);

    for (final match in _mutationCallPattern.allMatches(code)) {
      final method = match.group(1)!;
      final targetArgument = _mutationTargetArgument[method]!;
      final openingParenthesis = code.indexOf('(', match.start);
      final closingParenthesis = _balancedDelimiterEnd(
        code,
        openingParenthesis,
        '(',
        ')',
      );
      if (closingParenthesis == null) continue;
      final arguments = _topLevelArgumentRanges(
        code,
        openingParenthesis,
        closingParenthesis,
      );
      if (targetArgument >= arguments.length) continue;
      final targetRange = arguments[targetArgument];
      final targetExpression = code.substring(
        targetRange.start,
        targetRange.end,
      );
      if (!_isStreakTargetExpression(targetExpression, aliases.tables)) {
        continue;
      }

      writes.add(
        _DetectedStreakWrite(
          path: entry.key,
          matchedText: source.substring(match.start, targetRange.end),
          offset: match.start,
        ),
      );
    }

    writes.addAll(
      _detectReceiverStreakWrites(
        path: entry.key,
        source: source,
        code: code,
        aliases: aliases,
      ),
    );

    final patterns = <RegExp>[
      _streakCompanionPattern,
      _rawStreakMutationPattern,
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(source)) {
        writes.add(
          _DetectedStreakWrite(
            path: entry.key,
            matchedText: match.group(0)!,
            offset: match.start,
          ),
        );
      }
    }
  }
  writes.sort((left, right) {
    final pathOrder = left.path.compareTo(right.path);
    return pathOrder != 0 ? pathOrder : left.offset.compareTo(right.offset);
  });
  return writes;
}

_StreakAliases _resolveStreakAliases(String code) {
  final tableAliases = <String>{'streakStates'};
  final managerAliases = <String>{};
  final assignments = _lineageAssignments(code);

  for (var pass = 0; pass < assignments.length; pass++) {
    var changed = false;
    for (final assignment in assignments) {
      if (_isLineageExpression(
            assignment.$2,
            aliases: tableAliases,
            producers: _tableProducerMethods,
            directRoot: _isDirectTableRoot,
          ) &&
          tableAliases.add(assignment.$1)) {
        changed = true;
      }
      if (_isLineageExpression(
            assignment.$2,
            aliases: managerAliases,
            producers: _managerCompositionMethods,
            directRoot: _isDirectManagerRoot,
          ) &&
          managerAliases.add(assignment.$1)) {
        changed = true;
      }
    }
    if (!changed) break;
  }
  return _StreakAliases(tables: tableAliases, managers: managerAliases);
}

List<(String, String)> _lineageAssignments(String code) {
  final assignments = <(String, String)>[];
  for (final match in _lineageAssignmentPattern.allMatches(code)) {
    final start = match.end;
    var parentheses = 0;
    var brackets = 0;
    var braces = 0;
    int? end;
    for (var index = start; index < code.length; index++) {
      switch (code[index]) {
        case '(':
          parentheses++;
          break;
        case ')':
          parentheses--;
          break;
        case '[':
          brackets++;
          break;
        case ']':
          brackets--;
          break;
        case '{':
          braces++;
          break;
        case '}':
          braces--;
          break;
        case ';':
          if (parentheses == 0 && brackets == 0 && braces == 0) {
            end = index;
          }
          break;
      }
      if (end != null) break;
    }
    if (end == null) continue;
    assignments.add((match.group(1)!, code.substring(start, end).trim()));
  }
  return assignments;
}

List<_SourceRange> _topLevelArgumentRanges(
  String code,
  int openingParenthesis,
  int closingParenthesis,
) {
  final ranges = <_SourceRange>[];
  var start = openingParenthesis + 1;
  var parentheses = 0;
  var brackets = 0;
  var braces = 0;

  void addRange(int end) {
    var trimmedStart = start;
    var trimmedEnd = end;
    while (trimmedStart < trimmedEnd &&
        RegExp(r'\s').hasMatch(code[trimmedStart])) {
      trimmedStart++;
    }
    while (trimmedEnd > trimmedStart &&
        RegExp(r'\s').hasMatch(code[trimmedEnd - 1])) {
      trimmedEnd--;
    }
    if (trimmedStart < trimmedEnd) {
      ranges.add(_SourceRange(trimmedStart, trimmedEnd));
    }
  }

  for (
    var index = openingParenthesis + 1;
    index < closingParenthesis;
    index++
  ) {
    switch (code[index]) {
      case '(':
        parentheses++;
        break;
      case ')':
        parentheses--;
        break;
      case '[':
        brackets++;
        break;
      case ']':
        brackets--;
        break;
      case '{':
        braces++;
        break;
      case '}':
        braces--;
        break;
      case ',':
        if (parentheses == 0 && brackets == 0 && braces == 0) {
          addRange(index);
          start = index + 1;
        }
        break;
    }
  }
  addRange(closingParenthesis);
  return ranges;
}

bool _isStreakTargetExpression(String expression, Set<String> aliases) {
  var target = expression.trim();
  final namedArgument = RegExp(
    r'^[A-Za-z_$][A-Za-z0-9_$]*\s*:\s*(.+)$',
    dotAll: true,
  ).firstMatch(target);
  if (namedArgument != null) target = namedArgument.group(1)!.trim();

  if (RegExp(
    r'^(?:[A-Za-z_$][A-Za-z0-9_$]*\s*\.\s*)+streakStates$',
  ).hasMatch(target)) {
    return true;
  }
  return RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(target) &&
      aliases.contains(target);
}

List<_DetectedStreakWrite> _detectReceiverStreakWrites({
  required String path,
  required String source,
  required String code,
  required _StreakAliases aliases,
}) {
  final writes = <_DetectedStreakWrite>[];
  for (final match in _receiverMutationPattern.allMatches(code)) {
    final method = match.group(1)!;
    final statementBoundary = _statementBoundaryBefore(code, match.start);
    if (statementBoundary == null) continue;
    final receiverSegment = code.substring(statementBoundary + 1, match.start);
    final tableWrite =
        _tableReceiverMutationMethods.contains(method) &&
        _isTableReceiverExpression(receiverSegment, aliases.tables);
    final managerWrite =
        _managerReceiverMutationMethods.contains(method) &&
        _isManagerReceiverExpression(receiverSegment, aliases.managers);
    if (!tableWrite && !managerWrite) continue;

    writes.add(
      _DetectedStreakWrite(
        path: path,
        matchedText: source.substring(match.start, match.end),
        offset: match.start,
      ),
    );
  }
  return writes;
}

int? _statementBoundaryBefore(String code, int terminalOffset) {
  var parentheses = 0;
  var braces = 0;
  var brackets = 0;

  for (var index = terminalOffset - 1; index >= 0; index--) {
    switch (code[index]) {
      case ')':
        parentheses++;
        break;
      case '}':
        braces++;
        break;
      case ']':
        brackets++;
        break;
      case '(':
        if (parentheses == 0) {
          return braces == 0 && brackets == 0 ? index : null;
        }
        parentheses--;
        break;
      case '{':
        if (braces == 0) {
          return parentheses == 0 && brackets == 0 ? index : null;
        }
        braces--;
        break;
      case '[':
        if (brackets == 0) {
          return parentheses == 0 && braces == 0 ? index : null;
        }
        brackets--;
        break;
      case ';':
        if (parentheses == 0 && braces == 0 && brackets == 0) {
          return index;
        }
        break;
    }
  }

  return parentheses == 0 && braces == 0 && brackets == 0 ? -1 : null;
}

String? _trailingQualifiedIdentifier(String source) => RegExp(
  r'((?:[A-Za-z_$][A-Za-z0-9_$]*\s*\.\s*)*'
  r'[A-Za-z_$][A-Za-z0-9_$]*)\s*$',
).firstMatch(source)?.group(1)?.replaceAll(RegExp(r'\s+'), '');

bool _isTableReceiverExpression(String receiver, Set<String> aliases) {
  return _isLineageExpression(
    receiver,
    aliases: aliases,
    producers: _tableProducerMethods,
    directRoot: _isDirectTableRoot,
  );
}

bool _isDirectTableRoot(String target, Set<String> aliases) {
  if (aliases.contains(target)) return true;
  return target != 'managers.streakStates' &&
      !target.contains('.managers.') &&
      RegExp(r'^(?:[A-Za-z_$][A-Za-z0-9_$]*\.)+streakStates$').hasMatch(target);
}

bool _isManagerReceiverExpression(String receiver, Set<String> aliases) {
  final lineage = _lineageRoot(receiver, _managerCompositionMethods);
  if (lineage != null && _isDirectManagerRoot(lineage, aliases)) {
    return true;
  }
  var root = receiver.trimRight();
  while (root.endsWith(')')) {
    final closingParenthesis = root.length - 1;
    final openingParenthesis = _balancedDelimiterStart(
      root,
      closingParenthesis,
      '(',
      ')',
    );
    if (openingParenthesis == null) return false;

    var cursor = openingParenthesis - 1;
    while (cursor >= 0 && RegExp(r'\s').hasMatch(root[cursor])) {
      cursor--;
    }
    final methodEnd = cursor + 1;
    while (cursor >= 0 && RegExp(r'[A-Za-z0-9_$]').hasMatch(root[cursor])) {
      cursor--;
    }
    final method = root.substring(cursor + 1, methodEnd);
    while (cursor >= 0 && RegExp(r'\s').hasMatch(root[cursor])) {
      cursor--;
    }
    if (cursor < 0 ||
        root[cursor] != '.' ||
        !_managerCompositionMethods.contains(method)) {
      return false;
    }
    root = root.substring(0, cursor).trimRight();
  }

  final target = _trailingQualifiedIdentifier(root);
  if (target == null) return false;
  if (aliases.contains(target)) return true;
  return RegExp(
    r'^(?:[A-Za-z_$][A-Za-z0-9_$]*\.)*managers\.streakStates$',
  ).hasMatch(target);
}

bool _isDirectManagerRoot(String target, Set<String> aliases) {
  if (aliases.contains(target)) return true;
  return RegExp(
    r'^(?:[A-Za-z_$][A-Za-z0-9_$]*\.)*managers\.streakStates$',
  ).hasMatch(target);
}

bool _isLineageExpression(
  String expression, {
  required Set<String> aliases,
  required Set<String> producers,
  required bool Function(String target, Set<String> aliases) directRoot,
}) {
  final target = _lineageRoot(expression, producers);
  return target != null && directRoot(target, aliases);
}

String? _lineageRoot(String expression, Set<String> producers) {
  var root = expression.trimRight();
  while (true) {
    while (root.endsWith('.')) {
      root = root.substring(0, root.length - 1).trimRight();
    }
    if (!root.endsWith(')')) break;

    final closingParenthesis = root.length - 1;
    final openingParenthesis = _balancedDelimiterStart(
      root,
      closingParenthesis,
      '(',
      ')',
    );
    if (openingParenthesis == null) return null;

    var cursor = openingParenthesis - 1;
    while (cursor >= 0 && RegExp(r'\s').hasMatch(root[cursor])) {
      cursor--;
    }
    final methodEnd = cursor + 1;
    while (cursor >= 0 && RegExp(r'[A-Za-z0-9_$]').hasMatch(root[cursor])) {
      cursor--;
    }
    final method = root.substring(cursor + 1, methodEnd);
    while (cursor >= 0 && RegExp(r'\s').hasMatch(root[cursor])) {
      cursor--;
    }
    if (method.isNotEmpty && cursor >= 0 && root[cursor] == '.') {
      if (!producers.contains(method)) return null;
      root = root.substring(0, cursor).trimRight();
      continue;
    }

    root = root
        .substring(openingParenthesis + 1, closingParenthesis)
        .trimRight();
  }

  return _trailingQualifiedIdentifier(root);
}

int? _balancedDelimiterStart(
  String source,
  int closingOffset,
  String opening,
  String closing,
) {
  var depth = 0;
  for (var index = closingOffset; index >= 0; index--) {
    if (source[index] == closing) depth++;
    if (source[index] == opening) {
      depth--;
      if (depth == 0) return index;
    }
  }
  return null;
}

String _maskDartCommentsAndStrings(String source) {
  final output = StringBuffer();
  var index = 0;

  void maskCharacter(String character) {
    output.write(character == '\n' || character == '\r' ? character : ' ');
  }

  void maskRange(int start, int end) {
    for (var cursor = start; cursor < end; cursor++) {
      maskCharacter(source[cursor]);
    }
  }

  while (index < source.length) {
    if (index + 1 < source.length &&
        source[index] == '/' &&
        source[index + 1] == '/') {
      while (index < source.length && source[index] != '\n') {
        maskCharacter(source[index]);
        index++;
      }
      continue;
    }
    if (index + 1 < source.length &&
        source[index] == '/' &&
        source[index + 1] == '*') {
      var depth = 1;
      maskRange(index, index + 2);
      index += 2;
      while (index < source.length && depth > 0) {
        if (index + 1 < source.length &&
            source[index] == '/' &&
            source[index + 1] == '*') {
          depth++;
          maskRange(index, index + 2);
          index += 2;
        } else if (index + 1 < source.length &&
            source[index] == '*' &&
            source[index + 1] == '/') {
          depth--;
          maskRange(index, index + 2);
          index += 2;
        } else {
          maskCharacter(source[index]);
          index++;
        }
      }
      continue;
    }
    if (source[index] == "'" || source[index] == '"') {
      final quote = source[index];
      final isRaw =
          index > 0 &&
          (source[index - 1] == 'r' || source[index - 1] == 'R') &&
          (index < 2 || !RegExp(r'[A-Za-z0-9_$]').hasMatch(source[index - 2]));
      final triple =
          index + 2 < source.length &&
          source[index + 1] == quote &&
          source[index + 2] == quote;
      final delimiterLength = triple ? 3 : 1;
      maskRange(index, index + delimiterLength);
      index += delimiterLength;
      while (index < source.length) {
        if (triple &&
            index + 2 < source.length &&
            source[index] == quote &&
            source[index + 1] == quote &&
            source[index + 2] == quote) {
          maskRange(index, index + 3);
          index += 3;
          break;
        }
        if (!triple && source[index] == quote) {
          maskCharacter(source[index]);
          index++;
          break;
        }
        if (!isRaw && source[index] == '\\' && index + 1 < source.length) {
          maskRange(index, index + 2);
          index += 2;
          continue;
        }
        maskCharacter(source[index]);
        index++;
      }
      continue;
    }
    output.write(source[index]);
    index++;
  }
  return output.toString();
}

int? _balancedDelimiterEnd(
  String source,
  int openingOffset,
  String opening,
  String closing,
) {
  var depth = 0;
  for (var index = openingOffset; index < source.length; index++) {
    if (source[index] == opening) depth++;
    if (source[index] == closing) {
      depth--;
      if (depth == 0) return index;
    }
  }
  return null;
}

_SourceRange? _uniqueOwnerLifecycleWriteScope(String source) {
  final code = _maskDartCommentsAndStrings(source);
  final scopes = <_SourceRange>[];
  final methodPattern = RegExp(r'\b_mergeStreakState\s*\(');

  for (final match in methodPattern.allMatches(code)) {
    final openingParenthesis = code.indexOf('(', match.start);
    final closingParenthesis = _balancedDelimiterEnd(
      code,
      openingParenthesis,
      '(',
      ')',
    );
    if (closingParenthesis == null) return null;

    var cursor = closingParenthesis + 1;
    while (cursor < code.length && RegExp(r'\s').hasMatch(code[cursor])) {
      cursor++;
    }
    if (code.startsWith('async', cursor)) {
      cursor += 'async'.length;
      if (cursor < code.length && code[cursor] == '*') cursor++;
      while (cursor < code.length && RegExp(r'\s').hasMatch(code[cursor])) {
        cursor++;
      }
    }
    if (cursor >= code.length || code[cursor] != '{') continue;

    final closingBrace = _balancedDelimiterEnd(code, cursor, '{', '}');
    if (closingBrace == null) return null;
    scopes.add(_SourceRange(cursor + 1, closingBrace));
  }

  return scopes.length == 1 ? scopes.single : null;
}

bool _isApprovedStreakWrite(
  _DetectedStreakWrite write,
  Map<String, String> sources,
) {
  if (_approvedStreakWriters.contains(write.path)) return true;
  if (write.path != _ownerLifecycleMigration) return false;
  final source = sources[write.path];
  if (source == null) return false;
  final scope = _uniqueOwnerLifecycleWriteScope(source);
  return scope?.contains(write.offset) ?? false;
}

List<_DetectedStreakWrite> _approvedStreakWrites(
  Iterable<_DetectedStreakWrite> writes,
  Map<String, String> sources,
) => writes
    .where((write) => _isApprovedStreakWrite(write, sources))
    .toList(growable: false);

List<_DetectedStreakWrite> _forbiddenStreakWrites(
  Iterable<_DetectedStreakWrite> writes,
  Map<String, String> sources,
) => writes
    .where((write) => !_isApprovedStreakWrite(write, sources))
    .toList(growable: false);

void main() {
  test('operational streak writes stay inside the canonical authority', () {
    final sources = _productionDartSources();
    final writes = _detectStreakWrites(sources);
    final writerMatches = <String, int>{};
    for (final write in writes) {
      writerMatches.update(write.path, (count) => count + 1, ifAbsent: () => 1);
    }

    expect(
      writerMatches[_canonicalStreakAuthority],
      greaterThan(0),
      reason:
          'The architecture scan must observe the canonical streak writer at '
          '$_canonicalStreakAuthority.',
    );
    expect(
      writerMatches[_ownerLifecycleMigration],
      greaterThan(0),
      reason:
          'The only lifecycle migration exception must remain explicit at '
          '$_ownerLifecycleMigration.',
    );

    final forbiddenWriters = _forbiddenStreakWrites(writes, sources);
    expect(
      forbiddenWriters,
      isEmpty,
      reason:
          'Operational streak state writes are owned only by '
          '$_canonicalStreakAuthority. The lifecycle migration exception is '
          '$_ownerLifecycleMigration. Move or remove these forbidden writers:\n'
          '${forbiddenWriters.map((write) => '${write.path}:${write.offset}').join('\n')}',
    );
  });

  const detectorCases = <_DetectorCase>[
    _DetectorCase(
      'batch.replace',
      'void write(dynamic batch, dynamic streakStates, dynamic row) {'
          ' batch.replace(streakStates, row); }',
    ),
    _DetectorCase(
      'batch.insert',
      'void write(dynamic batch, dynamic streakStates, dynamic row) {'
          ' batch.insert(streakStates, row); }',
    ),
    _DetectorCase(
      'batch.insertAll',
      'void write(dynamic batch, dynamic streakStates, dynamic rows) {'
          ' batch.insertAll(streakStates, rows); }',
    ),
    _DetectorCase(
      'batch.insertAllOnConflictUpdate',
      'void write(dynamic batch, dynamic streakStates, dynamic rows) {'
          ' batch.insertAllOnConflictUpdate(streakStates, rows); }',
    ),
    _DetectorCase(
      'batch.insertFromSelect first-argument target',
      'void write(dynamic batch, dynamic query, dynamic streakStates) {'
          ' batch.insertFromSelect(streakStates, query); }',
    ),
    _DetectorCase(
      'batch.replaceAll',
      'void write(dynamic batch, dynamic streakStates, dynamic rows) {'
          ' batch.replaceAll(streakStates, rows); }',
    ),
    _DetectorCase(
      'batch.deleteWhere',
      'void write(dynamic batch, dynamic streakStates) {'
          ' batch.deleteWhere(streakStates, (row) => true); }',
    ),
    _DetectorCase(
      'batch.deleteAll',
      'void write(dynamic batch, dynamic streakStates) {'
          ' batch.deleteAll(streakStates); }',
    ),
    _DetectorCase(
      'aliased database.update',
      'void write(dynamic database, dynamic row) {'
          ' final target = database.streakStates;'
          ' database.update(target).write(row); }',
    ),
    _DetectorCase(
      'aliased database.delete',
      'void write(dynamic database) {'
          ' final target = database.streakStates;'
          ' database.delete(target).go(); }',
    ),
    _DetectorCase(
      'aliased database.into',
      'void write(dynamic database, dynamic row) {'
          ' final target = database.streakStates;'
          ' database.into(target).insert(row); }',
    ),
    _DetectorCase(
      'aliased batch.replace',
      'void write(dynamic database, dynamic batch, dynamic row) {'
          ' final target = database.streakStates;'
          ' batch.replace(target, row); }',
    ),
    _DetectorCase(
      'aliased batch.insert',
      'void write(dynamic database, dynamic batch, dynamic row) {'
          ' final target = database.streakStates;'
          ' batch.insert(target, row); }',
    ),
    _DetectorCase(
      'raw INSERT OR REPLACE',
      "void write(dynamic database) { database.customStatement("
          "'INSERT OR REPLACE INTO streak_states(owner_id) VALUES (?)'); }",
    ),
    _DetectorCase(
      'raw INSERT OR ROLLBACK',
      "void write(dynamic database) { database.customStatement("
          "'iNsErT  Or\tRoLlBaCk  InTo streak_states(owner_id) VALUES (?)'); }",
    ),
    _DetectorCase(
      'raw INSERT OR ABORT',
      "void write(dynamic database) { database.customStatement("
          "'INSERT\tOR ABORT\tINTO  streak_states(owner_id) VALUES (?)'); }",
    ),
    _DetectorCase(
      'raw INSERT OR FAIL',
      "void write(dynamic database) { database.customStatement("
          "'insert OR\tFAIL into streak_states(owner_id) VALUES (?)'); }",
    ),
    _DetectorCase(
      'raw INSERT OR IGNORE',
      "void write(dynamic database) { database.customStatement("
          "'Insert  or IGNORE  Into streak_states(owner_id) VALUES (?)'); }",
    ),
    _DetectorCase(
      'raw REPLACE',
      "void write(dynamic database) { database.customStatement("
          "'REPLACE INTO streak_states(owner_id) VALUES (?)'); }",
    ),
    _DetectorCase(
      'raw UPDATE OR ROLLBACK',
      "void write(dynamic database) { database.customStatement("
          "'uPdAtE  Or\tROLLBACK streak_states SET current_streak_days = 1'); }",
    ),
    _DetectorCase(
      'raw UPDATE OR ABORT',
      "void write(dynamic database) { database.customStatement("
          "'UPDATE\tOR ABORT  streak_states SET current_streak_days = 1'); }",
    ),
    _DetectorCase(
      'raw UPDATE OR FAIL',
      "void write(dynamic database) { database.customStatement("
          "'update OR\tFAIL streak_states SET current_streak_days = 1'); }",
    ),
    _DetectorCase(
      'raw UPDATE OR IGNORE',
      "void write(dynamic database) { database.customStatement("
          "'Update  or IGNORE  streak_states SET current_streak_days = 1'); }",
    ),
    _DetectorCase(
      'raw UPDATE OR REPLACE',
      "void write(dynamic database) { database.customStatement("
          "'UPDATE OR REPLACE streak_states SET current_streak_days = 1'); }",
    ),
  ];

  for (final detectorCase in detectorCases) {
    test('streak detector catches ${detectorCase.name}', () {
      final writes = _detectStreakWrites({
        'lib/features/example_writer.dart': detectorCase.source,
      });

      expect(
        writes,
        hasLength(1),
        reason:
            'The streak authority gate must detect ${detectorCase.name} as '
            'an operational streak_states write.',
      );
    });
  }

  test('streak detector resolves multi-hop alias for direct mutation', () {
    const source = '''
void write(dynamic database, dynamic row) {
  final first = database.streakStates;
  final second = first;
  final third = second;
  database.update(third).write(row);
}
''';

    expect(
      _detectStreakWrites({'lib/features/example_writer.dart': source}),
      hasLength(1),
      reason:
          'Alias resolution must reach a fixed point before direct mutation '
          'detection.',
    );
  });

  test('streak detector resolves multi-hop alias for batch mutation', () {
    const source = '''
void write(dynamic database, dynamic batch, dynamic row) {
  final first = database.streakStates;
  final second = first;
  final third = second;
  batch.replace(third, row);
}
''';

    expect(
      _detectStreakWrites({'lib/features/example_writer.dart': source}),
      hasLength(1),
      reason:
          'Alias resolution must reach a fixed point before batch mutation '
          'detection.',
    );
  });

  const tableReceiverMutations = <(String, String)>[
    ('insert', 'insert(row)'),
    ('insertOne', 'insertOne(row)'),
    ('insertAll', 'insertAll(rows)'),
    ('insertOnConflictUpdate', 'insertOnConflictUpdate(row)'),
    ('insertReturning', 'insertReturning(row)'),
    ('insertReturningOrNull', 'insertReturningOrNull(row)'),
    ('update', 'update().write(row)'),
    ('replaceOne', 'replaceOne(row)'),
    ('delete', 'delete().go()'),
    ('deleteOne', 'deleteOne(row)'),
    ('deleteWhere', 'deleteWhere((row) => true)'),
    ('deleteAll', 'deleteAll()'),
  ];

  for (final mutation in tableReceiverMutations) {
    test('streak detector catches TableStatements receiver ${mutation.$1}', () {
      final source =
          '''
void write(dynamic database, dynamic row, dynamic rows) {
  database.streakStates.${mutation.$2};
  final first = database.streakStates;
  final second = first;
  final third = second;
  third.${mutation.$2};
}
''';

      expect(
        _detectStreakWrites({'lib/features/example_writer.dart': source}),
        hasLength(2),
        reason:
            'Pinned Drift TableStatements.${mutation.$1} must be detected on '
            'both the direct streakStates receiver and its fixed-point alias.',
      );
    });
  }

  const managerReceiverMutations = <(String, String)>[
    ('create', 'create((row) => row())'),
    ('createReturning', 'createReturning((row) => row())'),
    ('createReturningOrNull', 'createReturningOrNull((row) => row())'),
    ('bulkCreate', 'bulkCreate((row) => [row()])'),
    ('replace', 'replace((row) => row())'),
    ('bulkReplace', 'bulkReplace((row) => [row()])'),
    ('update', 'update((row) => row())'),
    ('delete', 'delete()'),
  ];

  for (final mutation in managerReceiverMutations) {
    test('streak detector catches generated manager receiver ${mutation.$1}', () {
      final source =
          '''
void write(dynamic database, dynamic ownerId) {
  database.managers.streakStates.${mutation.$2};
  final first = database.managers.streakStates;
  final second = first;
  final third = second;
  third.${mutation.$2};
  database.managers.streakStates
      .filter((row) => row.ownerId.equals(ownerId))
      .${mutation.$2};
}
''';

      expect(
        _detectStreakWrites({'lib/features/example_writer.dart': source}),
        hasLength(3),
        reason:
            'Pinned generated-manager ${mutation.$1} must be detected on '
            'direct, fixed-point alias, and filtered streak manager receivers.',
      );
    });
  }

  test('streak detector follows manager filter producer alias', () {
    const source = '''
void write(dynamic database, dynamic ownerId) {
  final scoped = database.managers.streakStates
      .filter((row) => row.ownerId.equals(ownerId));
  scoped.delete();
}
''';

    expect(
      _detectStreakWrites({'lib/features/example_writer.dart': source}),
      hasLength(1),
      reason:
          'A manager returned by filter remains rooted at the streak manager '
          'when stored in an alias.',
    );
  });

  test(
    'streak detector follows manager producer alias chain to update and delete',
    () {
      const source = '''
void write(dynamic database) {
  final referenced = database.managers.streakStates.withReferences();
  final projected = referenced.withFields((fields) => [fields.ownerId]);
  final ordered = projected.orderBy((order) => [order.ownerId.asc()]);
  final limited = ordered.limit(1);
  limited.update((row) => row());
  limited.delete();
}
''';

      expect(
        _detectStreakWrites({'lib/features/example_writer.dart': source}),
        hasLength(2),
        reason:
            'withReferences, withFields, orderBy, and limit producer aliases '
            'must preserve manager lineage through update and delete.',
      );
    },
  );

  test(
    'streak detector follows direct manager withReferences and withFields chains',
    () {
      const source = '''
void write(dynamic database) {
  database.managers.streakStates.withReferences().delete();
  database.managers.streakStates
      .withFields((fields) => [fields.ownerId])
      .update((row) => row());
}
''';

      expect(
        _detectStreakWrites({'lib/features/example_writer.dart': source}),
        hasLength(2),
      );
    },
  );

  test('streak detector follows createAlias table lineage', () {
    const source = '''
void write(dynamic database, dynamic row) {
  final alias = database.streakStates.createAlias('s');
  database.update(alias).write(row);
}
''';

    expect(
      _detectStreakWrites({'lib/features/example_writer.dart': source}),
      hasLength(1),
      reason: 'A Drift createAlias table remains part of streak authority.',
    );
  });

  test('streak detector follows multi-hop createAlias table lineage', () {
    const source = '''
void write(dynamic database) {
  final alias = database.streakStates.createAlias('s');
  final second = alias;
  final third = second;
  database.delete(third).go();
}
''';

    expect(
      _detectStreakWrites({'lib/features/example_writer.dart': source}),
      hasLength(1),
    );
  });

  test('streak detector follows parenthesized table and manager receivers', () {
    const source = '''
void write(dynamic database, dynamic row) {
  (database.streakStates).insert(row);
  (database.managers.streakStates).delete();
}
''';

    expect(
      _detectStreakWrites({'lib/features/example_writer.dart': source}),
      hasLength(2),
    );
  });

  test('streak detector follows cascade table and manager receivers', () {
    const source = '''
void write(dynamic database, dynamic row) {
  database.streakStates..insert(row);
  database.managers.streakStates..delete();
}
''';

    expect(
      _detectStreakWrites({'lib/features/example_writer.dart': source}),
      hasLength(2),
    );
  });

  test(
    'streak detector keeps direct manager lineage through block callback',
    () {
      const source = '''
void write(dynamic database) {
  database.managers.streakStates
      .filter((row) {
        final nested = <String, List<List<int>>>{
          'values': <List<int>>[
            <int>[((row.ownerId.hashCode))],
          ],
        };
        final marker = 'string delimiter; stays inside the literal';
        // comment delimiter; with nested tokens ({[()]})
        if (((nested['values']![0][0]) >= 0)) {
          return marker.isNotEmpty;
        }
        return false;
      })
      .delete();
}
''';

      expect(
        _detectStreakWrites({'lib/features/example_writer.dart': source}),
        hasLength(1),
        reason:
            'Semicolons inside a balanced filter callback must not truncate '
            'the direct streak-manager receiver before delete.',
      );
    },
  );

  test(
    'streak detector keeps aliased manager lineage through block callback',
    () {
      const source = '''
void write(dynamic database) {
  final manager = database.managers.streakStates;
  manager
      .filter((row) {
        final nested = <String, List<List<int>>>{
          'values': <List<int>>[
            <int>[((row.ownerId.hashCode))],
          ],
        };
        final marker = 'string delimiter; stays inside the literal';
        /* comment delimiter; with nested tokens ({[()]}) */
        if (((nested['values']![0][0]) >= 0)) {
          return marker.isNotEmpty;
        }
        return false;
      })
      .update((value) => value());
}
''';

      expect(
        _detectStreakWrites({'lib/features/example_writer.dart': source}),
        hasLength(1),
        reason:
            'Semicolons inside a balanced filter callback must not truncate '
            'an aliased streak-manager receiver before update.',
      );
    },
  );

  const controlCases = <_DetectorCase>[
    _DetectorCase(
      'database.into control',
      'void write(dynamic database, dynamic row) {'
          ' database.into(database.streakStates).insert(row); }',
    ),
    _DetectorCase(
      'database.update control',
      'void write(dynamic database, dynamic row) {'
          ' database.update(database.streakStates).write(row); }',
    ),
    _DetectorCase(
      'database.delete control',
      'void write(dynamic database) {'
          ' database.delete(database.streakStates).go(); }',
    ),
    _DetectorCase(
      'raw INSERT control',
      "void write(dynamic database) { database.customStatement("
          "'INSERT INTO streak_states(owner_id) VALUES (?)'); }",
    ),
    _DetectorCase(
      'raw UPDATE control',
      "void write(dynamic database) { database.customStatement("
          "'UPDATE streak_states SET current_streak_days = 1'); }",
    ),
    _DetectorCase(
      'raw DELETE control',
      "void write(dynamic database) { database.customStatement("
          "'DELETE FROM streak_states WHERE owner_id = ?'); }",
    ),
    _DetectorCase(
      'raw REPLACE control',
      "void write(dynamic database) { database.customStatement("
          "'REPLACE INTO streak_states(owner_id) VALUES (?)'); }",
    ),
  ];

  for (final controlCase in controlCases) {
    test('streak detector retains ${controlCase.name}', () {
      final writes = _detectStreakWrites({
        'lib/features/example_writer.dart': controlCase.source,
      });

      expect(writes, hasLength(1));
    });
  }

  test('streak detector ignores ordinary select and read access', () {
    const source = '''
Future<void> readOnly(dynamic database) async {
  final direct = await database.select(database.streakStates).get();
  final target = database.streakStates;
  final aliased = await database.select(target).get();
  if (direct.isEmpty && aliased.isEmpty) return;
}
''';

    expect(
      _detectStreakWrites({'lib/features/example_reader.dart': source}),
      isEmpty,
    );
  });

  test('streak detector ignores TableStatements receiver reads', () {
    const source = '''
void readOnly(dynamic database) {
  database.streakStates.select();
  database.streakStates.selectOnly();
  final first = database.streakStates;
  final second = first;
  final third = second;
  third.all();
  third.count();
}
''';

    expect(
      _detectStreakWrites({'lib/features/example_reader.dart': source}),
      isEmpty,
    );
  });

  test('streak detector ignores generated manager receiver reads', () {
    const source = '''
void readOnly(dynamic database, dynamic ownerId) {
  database.managers.streakStates.get();
  database.managers.streakStates.watch();
  final first = database.managers.streakStates;
  final second = first;
  final third = second;
  third.count();
  database.managers.streakStates
      .filter((row) => row.ownerId.equals(ownerId))
      .exists();
}
''';

    expect(
      _detectStreakWrites({'lib/features/example_reader.dart': source}),
      isEmpty,
    );
  });

  test('streak detector keeps lineage producers and receivers read-only', () {
    const source = '''
void readOnly(dynamic database, dynamic ownerId) {
  final tableAlias = database.streakStates.createAlias('s');
  final tableAliasSecond = tableAlias;
  database.select(tableAliasSecond).get();
  (tableAliasSecond).select();
  database.streakStates..select()..selectOnly();

  final filtered = database.managers.streakStates
      .filter((row) => row.ownerId.equals(ownerId));
  final referenced = filtered.withReferences();
  final projected = referenced.withFields((fields) => [fields.ownerId]);
  final ordered = projected.orderBy((order) => [order.ownerId.asc()]);
  final limited = ordered.limit(1);
  limited.get();
  limited.watch();
  (database.managers.streakStates).count();
  database.managers.streakStates..get()..watch();
}
''';

    expect(
      _detectStreakWrites({'lib/features/example_reader.dart': source}),
      isEmpty,
    );
  });

  test(
    'streak detector keeps block-bodied manager callback reads non-writing',
    () {
      const source = '''
void readOnly(dynamic database) {
  database.managers.streakStates
      .filter((row) {
        final nested = <String, List<List<int>>>{
          'values': <List<int>>[
            <int>[((row.ownerId.hashCode))],
          ],
        };
        final marker = 'read delimiter; stays inside the literal';
        // read comment delimiter; with nested tokens ({[()]})
        return (((nested['values']![0][0]) >= 0)) && marker.isNotEmpty;
      })
      .get();

  final manager = database.managers.streakStates;
  manager
      .filter((row) {
        final nested = <List<int>>[
          <int>[((row.ownerId.hashCode))],
        ];
        final marker = 'watch delimiter; stays inside the literal';
        /* watch comment delimiter; with nested tokens ({[()]}) */
        return (((nested[0][0]) >= 0)) && marker.isNotEmpty;
      })
      .watch();
}
''';

      expect(
        _detectStreakWrites({'lib/features/example_reader.dart': source}),
        isEmpty,
      );
    },
  );

  test(
    'streak detector ignores read source in insertFromSelect target shape',
    () {
      const source = '''
void readOnly(dynamic database, dynamic batch, dynamic otherTable) {
  final sourceQuery = database.select(database.streakStates);
  batch.insertFromSelect(otherTable, sourceQuery);
}
''';

      expect(
        _detectStreakWrites({'lib/features/example_reader.dart': source}),
        isEmpty,
      );
    },
  );

  test(
    'streak detector ignores read source outside first batch target position',
    () {
      const source = '''
void readOnly(dynamic database, dynamic batch, dynamic otherTable) {
  batch.replaceAll(otherTable, rowsFrom(database.streakStates));
}
''';

      expect(
        _detectStreakWrites({'lib/features/example_reader.dart': source}),
        isEmpty,
      );
    },
  );

  test('streak detector leaves multi-hop select aliases non-writing', () {
    const source = '''
void readOnly(dynamic database) {
  final first = database.streakStates;
  final second = first;
  final third = second;
  database.select(third).get();
}
''';

    expect(
      _detectStreakWrites({'lib/features/example_reader.dart': source}),
      isEmpty,
    );
  });

  test('owner lifecycle exception is limited to _mergeStreakState', () {
    const source = '''
Future<void> _mergeStreakState(dynamic database, dynamic row) async {
  await database.into(database.streakStates).insert(row);
}

Future<void> writeOperationalStreak(dynamic database) async {
  await database.delete(database.streakStates).go();
}
''';
    final sources = <String, String>{_ownerLifecycleMigration: source};
    final writes = _detectStreakWrites(sources);
    final approved = _approvedStreakWrites(writes, sources);
    final forbidden = _forbiddenStreakWrites(writes, sources);

    expect(writes, hasLength(2));
    expect(
      approved,
      hasLength(1),
      reason:
          'Only the write lexically contained by _mergeStreakState may use '
          'the owner-lifecycle exception.',
    );
    expect(
      forbidden,
      hasLength(1),
      reason:
          'A streak write elsewhere in the owner repository must remain '
          'forbidden even though the file contains _mergeStreakState.',
    );
    expect(forbidden.single.matchedText, contains('delete'));
  });
}
