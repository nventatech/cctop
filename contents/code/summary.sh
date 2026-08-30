#!/usr/bin/env bash
# Copyright (C) 2026 NventaTech — GPL-3.0-or-later
# cctop - morning cost summary as a desktop notification.
# Meant to run from a systemd user timer; reuses fetch.sh for all data and
# follows the widget's language and privacy settings.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"

widget_cfg() {
  local rc="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"
  [ -f "$rc" ] || return
  awk -v key="$1" '
    /^\[/ { group = $0; next }
    $0 == "plugin=com.nventatech.cctop" { want = group "[Configuration][General]"; next }
    want != "" && group == want && index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }
  ' "$rc"
}

lang=$(widget_cfg language)
if [ -z "$lang" ]; then
  case "${LANG:-}" in pt*) lang=pt_BR ;; es*) lang=es ;; *) lang=en ;; esac
fi
privacy=$(widget_cfg privacy)

case "$lang" in
  pt_BR) tYesterday="ontem"; tWeek="7 dias"; tLimit="limite semanal"; tTitle="cctop — resumo da manhã" ;;
  es)    tYesterday="ayer"; tWeek="7 días"; tLimit="límite semanal"; tTitle="cctop — resumen de la mañana" ;;
  *)     tYesterday="yesterday"; tWeek="7 days"; tLimit="weekly limit"; tTitle="cctop — morning summary" ;;
esac

j=$(bash "$DIR/fetch.sh") || exit 1
[ -z "$j" ] && exit 1
jq -e '[.spark[].c] | add > 0' <<<"$j" >/dev/null || exit 1

yesterday=$(jq -r '.spark[-2].c // 0' <<<"$j")
week=$(jq -r '[.spark[].c] | add // 0' <<<"$j")
pct=$(jq -r '[.live.weekly.pct // 0, (.live.weekly_models // [])[].pct] | max // empty' <<<"$j")

if [ "$privacy" = "true" ]; then
  msg="$tYesterday \$••• · $tWeek \$•••"
else
  msg=$(LC_NUMERIC=C printf '%s $%.2f · %s $%.2f' "$tYesterday" "$yesterday" "$tWeek" "$week")
fi
[ -n "$pct" ] && msg="$msg · $tLimit ${pct}%"

notify-send -a cctop -i office-chart-bar "$tTitle" "$msg"
