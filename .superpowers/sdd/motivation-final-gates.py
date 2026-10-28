"""Serialized local verification; no install, publish, reset, or dependency sync."""
import base64
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
if Path.cwd().resolve() != root:
    raise SystemExit('Wrong worktree')
flutter = 'C:/Users/Phet/AppData/Local/Programs/flutter/bin/flutter.bat'
dart = 'C:/Users/Phet/AppData/Local/Programs/flutter/bin/dart.bat'
pwsh = 'C:/Users/Phet/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe'
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
stages = {
    'focused': [('f1-focused', flutter, ['test', '--no-pub', '--reporter', 'expanded',
        'test/screens/choose_mode_screen_test.dart',
        'test/screens/main_navigation_screen_test.dart',
        'test/screens/today_hub_screen_test.dart',
        'test/features/today_hub/today_hub_reader_test.dart',
        'test/features/adventure/presentation/adventure_pair_experience_test.dart',
        'test/features/adventure/presentation/today_experience_host_test.dart',
        'test/screens/learning_goals_screen_test.dart',
        'test/features/goals/learning_goal_use_cases_test.dart',
        'test/screens/study_reminder_settings_screen_test.dart',
        'test/features/reminders/study_reminder_use_cases_test.dart',
        'test/widgets/local_study_datetime_field_test.dart',
        'test/widgets/study_time_picker_test.dart',
        'test/utils/local_study_datetime_test.dart',
        'test/screens/mastery_dashboard_screen_test.dart',
        'test/features/companion',
        'test/screens/avatar_equipment_screen_test.dart',
        'test/widgets/reward_avatar_preview_test.dart',
        'test/features/rewards/reward_use_cases_test.dart',
        'test/features/rewards/avatar_progression_policy_test.dart',
        'test/features/rewards/economy_transaction_policy_test.dart',
        'test/screens/score_screen_test.dart',
        'test/screens/learning_calendar_screen_test.dart',
        'test/screens/achievements_screen_test.dart',
        'test/screens/study_planning_hub_screen_test.dart',
        'test/screens/profile_settings_screen_test.dart',
        'test/screens/setting_screen_test.dart',
        'test/features/learning/session_configuration_sheet_test.dart',
        'test/features/adventure/presentation/adventure_result_screen_test.dart',
        'test/features/learning/pair_matching/pair_matching_result_view_test.dart',
        'test/features/learning/pair_matching/pair_measurement_boundary_test.dart']),
        ('f1-accessibility', flutter, ['test', '--no-pub', '--reporter', 'expanded',
        'test/screens/accessibility_smoke_test.dart',
        'test/features/learning/pair_matching/pair_board_accessibility_test.dart',
        'test/config/m3_theme_test.dart'])],
    'analysis': [('f2-analysis', flutter, ['analyze', '--no-pub', 'lib', 'test', 'integration_test', 'test_driver', 'assets', 'tool', 'tools'])],
    'regression': [('f3-full', flutter, ['test', '--no-pub', '--exclude-tags', 'release-excluded', '--reporter', 'json'])],
    'integrations': [
        ('f4-' + label, flutter, ['test', '-d', 'flutter-tester', '--no-pub', '--timeout', '90s', '--reporter', 'expanded', 'integration_test/' + filename])
        for label, filename in [('core', 'field_trial_core_journey_test.dart'), ('controls', 'field_trial_feature_controls_test.dart'), ('media', 'field_trial_media_smoke_test.dart')]
    ],
    'backend': [
        ('f5-' + project, 'uv', ['run', '--project', 'backend/' + project, '--frozen', '--no-sync', '--group', 'dev', 'pytest', 'backend/' + project + '/tests', '-q'] +
         (['--ignore=backend/voice_api/tests/integration'] if project == 'voice_api' else []))
        for project in ['voice_api', 'ai_api', 'lexiquest_lm']
    ],
    'policies': [('f6-rules', 'npm.cmd', ['run', 'test:rules']), ('f6-auth', 'npm.cmd', ['run', 'test:auth'])],
    'contracts': [('f7-features', dart, ['run', 'tool/feature_contract/generate_feature_map.dart', '--check']),
                  ('f7-plan', dart, ['run', 'tool/final_test_plan/generate_final_test_plan.dart', '--check', '--source-commit', head])],
    'apk': [('f8-apk', flutter, ['build', 'apk', '--debug', '--no-pub'])],
}
stage = sys.argv[1]
stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
out = root / 'build/verification/motivation-ui-20260908/logs' / (stage + '-' + stamp)
out.mkdir()
if stage == 'cli':
    cli_out = root / 'build/verification/ui-implementation-20260908' / ('cli-motivation-' + stamp)
    commands = [('f5-cli', pwsh, ['-NoProfile', '-File', str(root / '.superpowers/sdd/ui-final-cli-tests.ps1'), '-EvidenceDirectory', str(cli_out)])]
else:
    commands = stages[stage]

def snapshot(name):
    path = out / name
    subprocess.run([sys.executable, '.superpowers/sdd/motivation-source-manifest.py', str(path)], check=True, stdout=subprocess.DEVNULL)
    return json.loads(path.read_text(encoding='utf-8'))

def quote(value):
    return "'" + value.replace("'", "''") + "'"

before = snapshot('whole-source-before.json')
records = []
for label, executable, arguments in commands:
    label = label.replace('_', '-')
    script = '& ' + quote(str(root / '.superpowers/sdd/device-current-source-gate.ps1'))
    script += ' -Label ' + quote('motivation-' + label) + ' -Executable ' + quote(executable)
    script += ' -ArgumentList @(' + ','.join(map(quote, arguments)) + ')'
    encoded = base64.b64encode(script.encode('utf-16-le')).decode('ascii')
    print('START ' + label, flush=True)
    result = subprocess.run([pwsh, '-NoProfile', '-EncodedCommand', encoded], cwd=root, capture_output=True)
    (out / (label + '.stdout.log')).write_bytes(result.stdout)
    (out / (label + '.stderr.log')).write_bytes(result.stderr)
    record = {'label': label, 'wrapperExit': result.returncode}
    try:
        record.update(json.loads(result.stdout.decode('utf-8-sig').strip()))
    except (ValueError, UnicodeError):
        record['parseError'] = True
    records.append(record)
    (out / 'results.json').write_text(json.dumps(records, indent=2), encoding='utf-8')
    print(json.dumps(record), flush=True)
    if result.returncode or record.get('gateExitCode') != 0:
        break
after = snapshot('whole-source-after.json')
stable = before['fingerprint'] == after['fingerprint'] and before['head'] == after['head']
ok = len(records) == len(commands) and stable and all(
    r.get('wrapperExit') == 0 and r.get('gateExitCode') == 0 and not r.get('parseError')
    for r in records)
summary = {'stage': stage, 'passed': ok, 'wholeSourceStable': stable,
           'wholeSourceFingerprint': before['fingerprint'], 'fileCount': before['fileCount'],
           'evidence': str(out), 'records': records}
(out / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
print(json.dumps({k: v for k, v in summary.items() if k != 'records'}), flush=True)
raise SystemExit(0 if ok else 1)
