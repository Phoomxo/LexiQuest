# PM8 local tool discovery — no execution evidence

2026-09-06, current task PowerShell environment, exact worktree C:/Users/Phet/.codex/worktrees/02fa/LexiQuest. Read-only Get-Command resolved git, flutter, dart, gitleaks, osv-scanner, node, npm, java, docker, adb and apkanalyzer. Initial discovery did not execute those tools; later CLI metadata checks are recorded below. No scan, backend test, emulator, Docker daemon, Android device, Flutter or build command was executed by this inventory.

Known paths relevant to later bounded checks:

- Gitleaks: C:/Users/Phet/AppData/Local/Microsoft/WinGet/Links/gitleaks.exe
- OSV Scanner: C:/Users/Phet/AppData/Local/Microsoft/WinGet/Links/osv-scanner.exe
- apkanalyzer: C:/Users/Phet/AppData/Local/Android/Sdk/cmdline-tools/latest/bin/apkanalyzer.bat
- Flutter/Dart: C:/Users/Phet/AppData/Local/Programs/flutter/bin
- Node: C:/Program Files/nodejs/node.exe; npm resolves npm.ps1 in that directory
- Java from PATH resolves Eclipse Adoptium JDK25.0.3.9; this does not establish the JDK selected by Flutter/Gradle. Use the existing configured build runtime and actual later build output, do not change global configuration based on this discovery.

Executable availability is not readiness, authentication, a running daemon/emulator, a connected device or a pass. Follow pm8-release-command-inventory.md only after final PM8 source freeze and exclusive Flutter/Dart ownership. No production service access, global installation/configuration change or real data processing is authorized by this note.

Later same-day metadata-only checks, both exit0: `gitleaks version` reports8.30.1; `gitleaks dir --help` confirms directory/file positional target, --redact (default100%), --config, --gitleaks-ignore-path, --no-banner, JSON --report-format/--report-path and bounded --timeout. `osv-scanner --version` reports2.4.0/scalibr0.4.5; its --help confirms current scan source command family. These help/version commands read no repository inputs and perform no vulnerability/secret query. Actual PM8 execution still uses the existing literal-six-lock wrapper; no recursive scan or fix command was run.
