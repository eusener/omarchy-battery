# Battery runtime

Record measured battery runtime from unplugging until reconnecting power, and
show remaining percentage against accumulated awake time as a bar chart. Use
Linux's monotonic clock so suspend and wall-clock changes do not add usage.

## Approach

Extend the existing Python collector and run a small local snapshot from the
plugin every 30 seconds, including while its popup is closed, and on UPower
power-source changes. This reuses the existing QML/Python stack. A separate
system service would outlive the plugin but would require an additional install
and lifecycle; in-memory QML tracking would lose history on shell reloads.

Persist only the current or latest session for each internal battery under
`$XDG_STATE_HOME/omarchy-battery/usage.json` (default `~/.local/state`). Save
atomically, bound input size and sample count, and report save failures without
breaking telemetry. Retain sessions across brief shell reloads. A reboot or
unobserved awake gap over 90 seconds closes the old session and starts a partial
observation if still on battery; never count an unobserved long gap as usage.
Starting the plugin on battery is explicitly labeled as a partial observation.

## UI

Reuse qs.Ui, Style, font, foreground, separators, locale and the existing panel
scroller. Add a section for each physical battery before condition details,
showing measured hours/minutes, start/current percentage, active/completed state,
and at most 24 time-aligned bars. Each bar is the remaining percentage at an
observed active-time coordinate, with a 0–100% vertical scale. A textual list
provides exact samples without depending on hover. Do not extrapolate runtime.

Show loading, no-session, missing percentage and persistence errors explicitly.
The latest completed session remains visible until the next unplug. No network,
new dependencies, system service, or edits to packaged Omarchy files.

## Verification

Use deterministic clocks and temporary sysfs/state fixtures for transitions,
suspend, restart/reboot, AC charge limits, missing data, multiple batteries,
bounded samples, corrupt state and failed writes. Run the repository checks and
render the new QML chart offscreen with representative data.
