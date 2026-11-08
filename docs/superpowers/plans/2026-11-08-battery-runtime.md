# Battery Runtime Implementation Plan

**Goal:** Measure awake time on battery and display percentage versus elapsed use.
**Architecture:** Python snapshots own measurements and local state; the existing
QML panel schedules snapshots and displays the current/latest session per battery.
**Tech Stack:** Python standard library, Qt Quick, Quickshell, Omarchy qs.Ui.
**Spec:** `docs/superpowers/specs/2026-11-08-battery-runtime-design.md`

## Constraints and review focus

Preserve the current plugin and theme; no network or system service. Count
monotonic awake seconds; never wall time or unknown observation gaps. Distinguish
external power from charging status. Save bounded, validated state atomically;
surface failures. Keep English and Portuguese catalogs aligned.

### Task 1: Runtime tracking

- [x] Add failing unittest cases for unplug/replug, awake clock/suspend, shell
  reload, reboot/gaps, missing percentages, AC limits and independent batteries.
- [x] Extend `battery.collect()` with percentage/status; implement `usage.py`
  with pure `advance(state, devices, on_battery, now, monotonic, boot_id)` and
  `snapshot(root, state_path)` with atomic persistence and bounded validation.
- [x] Verify corruption/write failures and run all Python tests.

### Task 2: Graph and panel integration

- [x] Add `UsageChart.qml`, using bounded time-aligned bars and a text disclosure.
- [x] Schedule `usage.py` every 30 seconds and on power-source changes in
  `Panel.qml`; preserve the five-second open-panel telemetry cadence.
- [x] Add translated loading/empty/partial/completed/error text and duration units.
- [x] Render chart with fixture sessions using Qt offscreen; run syntax checks.

### Task 3: Documentation and verification

- [x] Update `DESIGN.md`, README, manifest and check script for the new behavior.
- [x] Run `bash scripts/check.sh`, the UI static audit and `git diff --check`.
- [x] Review the final patch for inaccurate time, stale data, state loss and layout
  issues; report actual verification and any live-session limitation.

## Verification evidence

- `bash scripts/check.sh`: 29 Python tests passed; chart-model JavaScript tests,
  catalogs/manifest and both QML syntax checks passed.
- Strict premium UI static audit: no findings.
- `git diff --check`: passed.
- Quickshell offscreen chart render inspected; full plugin initialization tested
  in an isolated Wayland instance with state confined to /tmp.
- Independent review found and reproduced a multi-monitor persistence race,
  oversized numeric state failure, and loss of the initial sample after an
  unknown power interval. Regression tests failed before the fixes and pass now.
- Installed 1.1.0 in the user plugin with a full backup. Hot reload retained the
  earlier component, so the Omarchy Shell was restarted. The live plugin created
  its own BAT0 session and began recording samples while the popup was closed.
- Actual physical unplug/replug and suspend/resume were covered by deterministic
  fixtures; these hardware transitions were not forced on the user's machine.
