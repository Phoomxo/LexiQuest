### Task 1: Freeze the truthful Prototype feature contract

**Files:**

- Create: `docs/prototype/feature-inventory.md`
- Create: `tool/cli/prototype-production-paths.allowlist.json`
- Create: `tool/cli/tests/prototype-production-paths.tests.ps1`
- Modify: `README.md`

**Interfaces:**

- Consumes: tracked `lib/**/*.dart`, `lib/navigation/app_route.dart`,
  `lib/navigation/app_router.dart`, `lib/screens/main_navigation_screen.dart`,
  `lib/screens/choose_mode_screen.dart`, and the approved Real Local-First
  Prototype design.
- Produces: an inventory with one row per visible entry point and an exact
  `{path, rule}` production-debt allowlist consumed by the PowerShell contract.

- [ ] **Step 1: Write the inventory schema**

Create `docs/prototype/feature-inventory.md` with these required columns:

```text
Feature ID | Visible entry | Screen/route | Current data/device/provider
Offline behavior | Permission/configuration | Truthful unavailable state
Known blocker | Target phase | Evidence
```

The document must:

- enumerate all five primary destinations, drawer entries, settings entries,
  account routes, learning/practice entries, scanner/speech entries, economy,
  research/export, and hidden/disabled entries;
- distinguish typed routes from direct `MaterialPageRoute` construction;
- identify direct screen imports of Firebase, HTTP, speech, or other plugins;
- classify curated product content separately from fabricated user history;
- state `ready`, `degraded`, `blocked`, or `not exposed` without claiming that
  a menu label proves the feature works.

- [ ] **Step 2: Create the exact known-debt allowlist**

Create JSON with this shape:

```json
{
  "schemaVersion": 1,
  "entries": [
    {
      "path": "lib/screens/object_scanner_screen.dart",
      "rule": "simulated-device-result",
      "targetPhase": 3,
      "featureId": "device.object-scanner"
    }
  ]
}
```

Include only confirmed production blockers from the bounded scan. Do not
allowlist statistical terms such as `sampleStandardDeviation`, legitimate quiz
shuffling, test-only classes, or documented curated packs.

- [ ] **Step 3: Write the bounded production-path contract**

`tool/cli/tests/prototype-production-paths.tests.ps1` must:

1. obtain candidate paths from `git ls-files` under `lib/` only;
2. scan file contents for named rules covering sample user history, mock
   production provider, simulated device result, random fabricated
   measurement, placeholder transaction/feature, canned AI response, direct
   screen Firebase/HTTP access, and direct screen plugin access;
3. emit only relative path, rule, target phase, and counts—never matching
   source text;
4. compare exact `{path, rule}` pairs to the JSON allowlist;
5. fail on malformed JSON, duplicate entries, unknown rule names, missing
   files, new findings, or stale entries;
6. support `-Strict`, which also fails if any allowlisted debt remains;
7. assert the inventory names every allowlisted feature and every production
   screen file reachable from the current menu surfaces.

- [ ] **Step 4: Verify the baseline contract**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/prototype-production-paths.tests.ps1
```

Expected: exit `0`, no new/stale findings, and a non-zero explicit known-debt
count.

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/prototype-production-paths.tests.ps1 -Strict
```

Expected: exit `1` only because the documented known-debt count is non-zero.

- [ ] **Step 5: Link the active inventory and commit**

Add `docs/prototype/feature-inventory.md` to README's Current prototype
direction block.

```powershell
git add -- README.md docs/prototype/feature-inventory.md tool/cli/prototype-production-paths.allowlist.json tool/cli/tests/prototype-production-paths.tests.ps1
git commit -m "docs: freeze the prototype feature contract"
```

---

