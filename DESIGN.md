# Battery details

Extend the existing Omarchy power panel using its typography, foreground colors,
spacing, KeyboardPanel, separators and profile controls. No new visual theme.

Show physical battery telemetry after the existing energy controls. Bound the
popup to the screen and allow wheel, touch and Page Up / Page Down scrolling.
Wrap long identifiers, render every hardware string as plain text, and retain
the shell's keyboard navigation and Escape behavior.

The default view emphasizes health, degradation and cycles in three quiet metric
surfaces. Compare design, full and remaining capacity with aligned bars sharing
the design-capacity scale. Keep manufacturer and model visible; place the other
identity and electrical fields behind a technical-details disclosure (button or
D key). Show a stable charge-state subtitle; avoid rotating copy and pulsing
decoration. Use the active theme's corner radius and low-alpha foreground fills.

Read detailed local sysfs telemetry while the panel is open, on opening and every
five seconds. Separately, measure runtime every 30 seconds while the battery
widget is loaded, on power-source changes, and on panel refreshes, including
with the popup closed. Use CLOCK_MONOTONIC to exclude suspend. Persist the latest
session for each battery atomically in XDG_STATE_HOME/omarchy-battery/usage.json.
Only bridge observations within the same boot and at most 90 awake seconds
apart; otherwise start a clearly labeled partial observation. Reconnecting AC
ends the session even when a charge limit means the battery is not charging.

Place real usage before battery condition, using the existing MetricCard,
DetailLine, PanelSectionHeader and panel scroller. UsageChart owns the graph:
remaining percentage on a fixed 0–100% vertical scale, actual accumulated awake
time on the horizontal scale, at most 24 observed bars. Label both axes and
provide a button to show the plotted readings as text. Keep duration, partial
observation, loading, empty and persistence-error states explicit. Keep the
latest completed session visible until the next unplug. Do not extrapolate
total runtime from a partial discharge. Chart colors and typography are owned
by the active bar; spacing and geometry follow qs.Commons.Style.

Use Portuguese and English catalogs following the shell language. Format numbers
with the shell locale. Missing readings say “Não informado” / “Not reported”.
Brand and part number are independent firmware fields, never inferred from model
or manufacturer. Capacities use Wh for energy or mAh for charge-only drivers.
Health is full charge capacity divided by design capacity; degradation is its
complement, bounded at zero. Remaining charge is a separate instantaneous reading.

Canonical component owner: `/usr/share/omarchy/shell/Ui` (read only).
Runtime token owner: `qs.Commons.Style` and the active bar theme.
