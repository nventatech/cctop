# Changelog

## Unreleased (1.6.0)

Added
- Threshold notifications escalate: the configured threshold, then 95% and
  100%, instead of one warning per window
- Pace notification when the current burn is set to hit 100% before the
  window closes, while there is still time to slow down
- Lockout reason from the API on the session and weekly cards, with a
  notification
- Reset notifications say how full the new window already is and when it
  closes

Changed
- Near a limit (90% or more) the live data refreshes every minute instead of
  every four, so the percentage on screen is the one that matters
- Codex and Gemini are marked best effort in the README: their readers are
  validated with synthetic fixtures only

Fixed
- Half-width weekly cards cut the reset time ("resets Sat …"); they now show
  only the time, full-width cards keep the word
- Repeated threshold notifications and false "limit reset" ones: the API
  stamps the reset time with the microsecond of the request, so every poll
  looked like a new window. Reset times are now rounded to the minute, which
  also fixes the odd "resets Mon 19:59" instead of 20:00
- Half-width weekly cards still cut the day: the popup is wider (27 grid units
  instead of 23), which leaves the reset time and the pace on one line


## 1.5.0 — 2026-08-26

Added
- Click the big number to switch its window: this month, today, last 7 days,
  last 30 days
- Plan value line in the subscriptions card: this month's Claude usage at API
  rates and how many times the plan price that is
- Pace warning on the weekly cards, like the session card already had
- Budget notification at 80%, before the one at 100%
- Notification when a window that was above the threshold resets
- CSV export of the last 30 days (per day and model) from the footer
- Footer shows how long ago the data was collected, and warns when the
  collector failed (old numbers were shown silently)
- Polish: the big number, progress bars and the 7-day bars animate; hovering
  a day shows its cost; today vs yesterday delta; the window name is a
  visible "▾" chip; colored dot in the panel label; provider share bar
  hidden with a single provider
- Language "System" (default): follows the desktop locale
- Per-model pricing for Codex (gpt-5.x family, gpt-4o, o-series) and Gemini
  (2.5/2.0/1.5); one flat rate before
- Morning summary follows the widget language and privacy mode

Fixed
- Morning summary notified zeros when the PC booted after 08:00: the timer
  fired before the network was up and `bunx ccusage` needs the registry.
  The script now fails (and the unit retries) instead of notifying, the
  README unit waits for the network, and a global `ccusage` install is used
  when present
- Collector cache moved to `~/.cache/cctop`: numbers survive a reboot and a
  failed run keeps the last known values instead of dropping to zero
- Top projects: every repo named `code`/`src` showed up under that name; the
  label now keeps the parent folder ("app/code") and home sessions show as `~`
- Threshold notifications repeated after a plasmashell restart; the window
  is now remembered in the widget settings
- Debug log only written with `CCTOP_DEBUG=1`; cache entries older than 60 days are pruned


## 1.4.0 — 2026-08-15

Added
- One card per model-scoped weekly limit (before, only the first one showed up)
- The limit the API reports as active is outlined in the popup
- Pace warning on the session card: how long until the 5h window hits 100% at
  the current burn rate
- Extra usage credits card, when the account has credits enabled
- Panel mode `Weekly %`, showing whichever weekly limit is tightest
- Option to follow the system theme, for light Plasma desktops

Fixed
- The model-scoped limit was labelled with the model in use, so switching
  models relabelled a limit that belongs to another model. The name now comes
  from the API
- Gemini: the monthly total summed the whole telemetry log regardless of date,
  and today's spend was always zero
- OpenAI: the month was filtered by file mtime, so a session started last month
  counted in full this month. Filtered by event timestamp now
- Notification text is passed as a quoted argument instead of being pasted into
  the command line

Changed
- The two ccusage runs happen side by side and the daily payload is cached
  briefly: about half the CPU per refresh cycle

## 1.3.1 — 2026-07-27

Fixed the model label, the month rollover and a progress bar overflow; the
collector path is quoted, so an install path with spaces works.

## 1.3.0 — 2026-07-17

Last 6 months bar chart, weekly limit notifications and the session reset
countdown panel mode.

## 1.2.0 — 2026-07-15

Extra subscriptions in the settings, morning summary script, end-of-month
projection and last month comparison, top projects and by-model breakdown, and
tmpfs caching for the slow collectors.

## 1.1.0 — 2026-07-08

App icon, monthly budget tracking, configurable refresh interval, privacy mode,
panel scroll cycling and ChatGPT subscription auto-detection.

## 1.0.0 — 2026-07-07

First release: panel indicator, monthly spend per provider, live limits and
subscription detection.
