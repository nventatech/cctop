# Descrição das lojas — cctop (KDE Store e extensions.gnome.org)

Um arquivo, os campos das duas lojas. Seção EGO no fim. O que está no ar hoje é o texto da 1.6.0
(2026-08-31).
Ao publicar: colar DESCRIPTION no campo de descrição, colar a entrada nova do
CHANGELOG no campo de changelog, e atualizar a linha "no ar desde" aqui.

Texto plano, sem BBCode — a KDE Store não renderiza marcação. Entrada de
changelog no topo, uma por versão.

Diferente do Nexus: a KDE Store não tem limite de 250 chars por entrada nem de
350 no summary. Entrada tem o tamanho que precisar pra explicar — sem encher
linguiça, mas sem cortar informação pra caber num limite que não existe.

=== NAME ===

cctop

=== SHORT SUMMARY ===

AI usage and cost monitor for the KDE Plasma panel. Reads local logs only — no
accounts, no API keys, no telemetry.

=== DESCRIPTION ===

AI usage and cost monitor for the KDE Plasma panel. Tracks what your AI coding tools really cost — with 100% local data: no accounts, no API keys, no telemetry.

PANEL — live Claude Code session usage % (green → yellow → red), weekly limit %, today's spend or subscriptions total. Scroll to cycle modes.

POPUP

• Monthly spend per provider (Claude, OpenAI/Codex CLI, Gemini CLI) with stacked bar. Click the big number to switch window: this month, today, last 7 days, last 30 days

• End-of-month projection and last-month comparison

• Live limits: current 5h session, weekly all-models and one card per model-scoped limit, from the same endpoint as Claude Code's /usage — the limit that is currently biting is outlined

• Pace warning: how long until a window hits 100% at the current burn rate, or where the usage lands at the reset

• Lockout reason, when the API reports the account is locked out of a window

• Extra usage credits, when the account has them enabled

• Top projects and by-model cost breakdown for the month

• Last 7 days chart, last 6 months chart and recent sessions

• Subscription auto-detection (Claude and ChatGPT plans) + your own extra subscriptions, and what this month's usage would cost at API rates

• Monthly budget with progress bar and notifications

• Notifications when a limit crosses your threshold, again at 95% and 100%, when the pace is set to overshoot the window, when a window is locked, and when it resets

• CSV export of the last 30 days, per day and model

• Privacy mode, optional morning summary (systemd timer)

• Dark by default, or follow the system theme

• English, Português (Brasil), Español

Requires Plasma 6, jq, curl and Node.js or Bun. Claude data needs Claude Code installed. Providers appear automatically when their CLI is used on the machine.

Also available as a GNOME Shell extension, same repository: github.com/nventatech/cctop

=== CHANGELOG (1.7.0, rascunho) ===

GNOME Shell extension in the same repository, with the same panel indicator,
popup, notifications and settings. The repository is now split into plasma/,
gnome/ and shared/. No change in the widget itself.

=== CHANGELOG (1.6.0) ===

Threshold notifications now escalate: your threshold, then 95%, then 100%.
New pace notification while there is still time to slow down, and the lockout
reason from the API on the session and weekly cards. Fixed repeated threshold
notifications and false "limit reset" ones: the API stamps the reset time with
the microsecond of the request, so every poll looked like a new window. Wider
popup, so the weekly cards fit the reset time and the pace on one line.

=== CHANGELOG (1.5.0) ===

Click the big number to switch window: this month, today, last 7 days, last
30 days. Plan value line, CSV export of the last 30 days, budget notification
at 80%, and a notification when a window that was full resets. Per-model
pricing for Codex and Gemini. Fixed the morning summary notifying zeros when
the PC booted after it was due, and the cost dropping to zero when a collector
failed.

=== CHANGELOG (1.4.0) ===

One card per model-scoped weekly limit, with the active one outlined. Pace
warning on the session card. Extra usage credits card. Weekly % panel mode and
an option to follow the system theme. Fixed the scoped limit being labelled
with the model in use instead of its own, and the Gemini and OpenAI monthly
totals.

=== CHANGELOG (1.3.1) ===

Fixed the model label, the month rollover and a progress bar overflow. The
collector path is quoted, so an install path with spaces works.

=== CHANGELOG (1.3.0) ===

Last 6 months bar chart, weekly limit notifications and the session reset
countdown panel mode.

=== CHANGELOG (1.2.0) ===

Extra subscriptions in the settings, morning summary script, end-of-month
projection and last-month comparison, top projects and by-model breakdown.

=== CHANGELOG (1.1.0) ===

App icon, monthly budget tracking, configurable refresh interval, privacy mode,
panel scroll cycling and ChatGPT subscription auto-detection.

=== CHANGELOG (1.0.0) ===

First release: panel indicator, monthly spend per provider, live limits and
subscription detection.

## Histórico da descrição

- Até 1.3.1: painel sem o modo weekly; limites descritos como "current 5h
  session and weekly limits" (sem card por modelo nem destaque do ativo); sem
  aviso de ritmo, sem créditos extras, sem opção de tema do sistema.
- 1.4.0 (no ar): acrescentou card por modelo, aviso de ritmo, créditos extras e
  tema do sistema.
- 1.6.0 (rascunho acima): acrescentou clique no número grande, bloqueio,
  6 meses, valor do plano, níveis de notificação, aviso de ritmo por
  notificação e export CSV. A ressalva de best effort do Codex/Gemini fica só
  no README, fora da loja.

## extensions.gnome.org (EGO)

Campos do upload: só o zip. Nome, descrição, url e versões do shell vêm do
`metadata.json`. A descrição da página é o campo `description` do metadata
(texto plano, curto). Screenshot é enviado na página da extensão depois da
aprovação. Versão é atribuída pela EGO (não pôr `version` no metadata;
`version-name` é o que aparece para o usuário).

=== EGO metadata description (atual) ===

AI usage and cost monitor: Claude Code live limits, monthly spend per provider, subscriptions. 100% local data.

=== EGO texto longo (pra página, se a EGO pedir na review) ===

AI usage and cost monitor for the top bar. Tracks what your AI coding tools really cost with 100% local data: no accounts, no API keys, no telemetry.

Top bar: live Claude Code session usage % (green → yellow → red), weekly limit %, today's spend or subscriptions total. Scroll to cycle modes.

Popup: monthly spend per provider (Claude, OpenAI/Codex CLI, Gemini CLI), end-of-month projection, live 5h and weekly limits with pace warning and lockout reason, extra usage credits, top projects and by-model breakdown, last 7 days and 6 months charts, recent sessions, subscriptions and plan value, monthly budget, notifications, CSV export, privacy mode. English, Português (Brasil), Español.

Requires jq, curl and ccusage (Node.js or Bun). Claude data needs Claude Code installed. The extension runs the bundled collector script (bash) and calls the Claude usage endpoint with the OAuth token Claude Code already keeps locally.
