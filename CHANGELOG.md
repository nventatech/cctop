# Changelog

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
