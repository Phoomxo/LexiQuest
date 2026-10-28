"""Bounded structural review of generated Drift; not a runtime acceptance gate.

Checks every generated column against its handwritten declaration and records
unresolved comparisons instead of claiming regeneration or analyzer equivalence.
"""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[6]
OUT = Path(__file__).resolve().parent
generated = ROOT / 'lib/data/local/app_database.g.dart'
text = generated.read_text(encoding='utf-8')
source = (ROOT / 'lib/data/local/app_database.dart').read_text(encoding='utf-8')
declared = re.search(r'@DriftDatabase\(\s*tables:\s*\[(.*?)\]', source, re.S).group(1)
expected = re.findall(r'\b\w+\b', declared)
sources = {}
parents = {}
for path in (ROOT / 'lib/data/local/tables').glob('*.dart'):
    body = path.read_text(encoding='utf-8')
    matches = list(re.finditer(r'class (\w+) extends (\w+)\s*\{', body))
    for i, match in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(body)
        sources[match[1]] = (str(path.relative_to(ROOT)).replace('\\', '/'), body[match.end():end])
        parents[match[1]] = match[2]
tables = list(re.finditer(r'^class \$(\w+)Table extends (\w+)\s', text, re.M))
assert len(tables) == len(expected) == 50
assert {m[2] for m in tables} == set(expected)
rows = []
issues = []
type_map = {'Text': 'String', 'Int': 'int', 'Bool': 'bool', 'Real': 'double', 'DateTime': 'DateTime', 'Blob': 'Uint8List'}
for i, table in enumerate(tables):
    end = tables[i + 1].start() if i + 1 < len(tables) else text.index('abstract class _$AppDatabase')
    block = text[table.start():end]
    table_name = re.search(r"static const String \$name = '([^']+)'", block)[1]
    source_path, handwritten = sources[table[2]]
    parent = parents[table[2]]
    while parent != 'Table':
        handwritten += '\n' + sources[parent][1]
        parent = parents[parent]
    declarations = {m[2]: (m[1], m[3]) for m in re.finditer(r'(Text|Int|Bool|Real|DateTime|Blob)Column\s+get\s+(\w+)\s*=>\s*(.*?);', handwritten, re.S)}
    columns = list(re.finditer(r'late final GeneratedColumn<([^>]+)>\s+(\w+)\s*=\s*GeneratedColumn<[^>]+>\(', block))
    names = [m[2] for m in columns]
    if set(names) != set(declarations):
        issues.append([table_name, 'declaration-set', sorted(set(names) ^ set(declarations))])
    listed = re.search(r'get \$columns => \[(.*?)\];', block, re.S)
    assert listed and re.findall(r'\b\w+\b', listed[1]) == names, table_name
    cols = []
    for j, column in enumerate(columns):
        stop = columns[j + 1].start() if j + 1 < len(columns) else listed.start()
        definition = block[column.end():stop]
        sql = re.match(r"\s*'([^']+)',\s*aliasedName,\s*(true|false),", definition)
        assert sql, (table_name, column[2])
        typ, expr = declarations[column[2]]
        nullable = '.nullable()' in expr
        if nullable != (sql[2] == 'true') or type_map[typ] != column[1]:
            issues.append([table_name, column[2], 'type/nullability', typ, nullable, column[1], sql[2]])
        snake = re.sub(r'(?<!^)(?=[A-Z])', '_', column[2]).lower()
        named = re.search(r"\.named\('([^']+)'\)", expr)
        if sql[1] != (named[1] if named else snake):
            issues.append([table_name, column[2], 'sql-name', sql[1]])
        default = re.search(r'\.withDefault\((.*?)\)\s*\(', expr, re.S)
        if default and re.sub(r'\s+', '', default[1]) not in re.sub(r'\s+', '', definition):
            issues.append([table_name, column[2], 'default-needs-review', default[1]])
        # Mapping and companion serialization are distinct generated paths.
        mapping = "data['${effectivePrefix}" + sql[1] + "']"
        if mapping not in block or ("map['" + sql[1] + "']") not in block:
            issues.append([table_name, column[2], 'serialization-path-missing'])
        cols.append({'field': column[2], 'sql': sql[1], 'type': column[1], 'nullable': nullable,
                     'source': re.sub(r'\s+', ' ', expr).strip(),
                     'generated': re.sub(r'\s+', ' ', definition.split('static const VerificationMeta')[0]).strip()})
    key = re.search(r'get \$primaryKey => (\{.*?\});', block, re.S)
    source_key = re.search(r'get primaryKey => (\{.*?\});', handwritten, re.S)
    if source_key and re.sub(r'\s+', '', key[1]) != re.sub(r'\s+', '', source_key[1]):
        issues.append([table_name, 'primary-key-mismatch'])
    unique = re.search(r'get uniqueKeys => (\[.*?\]);', block, re.S)
    source_unique = re.search(r'get uniqueKeys => (\[.*?\]);', handwritten, re.S)
    compact = lambda value: re.sub(r'\s+', '', re.sub(r'//[^\n]*', '', value[1])) if value else None
    if compact(unique) != compact(source_unique):
        issues.append([table_name, 'unique-key-mismatch'])
    rows.append({'table': table_name, 'sourceClass': table[2], 'sourcePath': source_path,
                 'generatedStartLine': text[:table.start()].count('\n') + 1,
                 'primaryKey': key[1] if key else None,
                 'uniqueKeys': unique[1] if unique else None, 'columns': cols})
report = {'generatedSha256': hashlib.sha256(generated.read_bytes()).hexdigest(),
          'tables': rows, 'columnCount': sum(len(r['columns']) for r in rows),
          'issues': issues, 'runtimeAcceptance': False,
          'limitations': 'Regex structural comparison, not Dart AST, regeneration, constraints execution, or manual reading of every generated line.'}
(OUT / 'generated-drift-structural-review.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
print(json.dumps({'tables': len(rows), 'columns': report['columnCount'], 'issues': issues}))
