#!/usr/bin/env bash
# cctop - Waybar module: panel text, severity class and summary tooltip.
# Copyright (C) 2026 NventaTech — GPL-3.0-or-later
set -u
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
FETCH="$DIR/../shared/code/fetch.sh"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/cctop"
MODE_FILE="$STATE_DIR/waybar-mode"
LAST="$STATE_DIR/waybar-last.json"
SIGNAL="${CCTOP_WAYBAR_SIGNAL:-8}"
MODES=(session weekly today subs reset)
mkdir -p "$STATE_DIR"

mode=$(cat "$MODE_FILE" 2>/dev/null || echo session)
idx=0
for i in "${!MODES[@]}"; do [ "${MODES[$i]}" = "$mode" ] && idx=$i; done
n=${#MODES[@]}

case "${1:-}" in
  next) echo "${MODES[$(( (idx + 1) % n ))]}" > "$MODE_FILE"; pkill -RTMIN+"$SIGNAL" -x waybar; exit 0 ;;
  prev) echo "${MODES[$(( (idx + n - 1) % n ))]}" > "$MODE_FILE"; pkill -RTMIN+"$SIGNAL" -x waybar; exit 0 ;;
  refresh) pkill -RTMIN+"$SIGNAL" -x waybar; exit 0 ;;
esac

case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
  pt*) S='{"month":"neste mês","today":"hoje","session":"sessão","resets":"reseta","weeklyAll":"todos os modelos","plan":"plano","block":"bloco atual","left":"restantes","stale":"coleta falhou, mostrando último dado","noLive":"sem dados ao vivo","wd":["dom","seg","ter","qua","qui","sex","sáb"]}' ;;
  es*) S='{"month":"en este mes","today":"hoy","session":"sesión","resets":"se reinicia","weeklyAll":"todos los modelos","plan":"plan","block":"bloque actual","left":"restantes","stale":"la recolección falló, mostrando el último dato","noLive":"sin datos en vivo","wd":["dom","lun","mar","mié","jue","vie","sáb"]}' ;;
  *)   S='{"month":"this month","today":"today","session":"session","resets":"resets","weeklyAll":"all models","plan":"plan","block":"current block","left":"left","stale":"collector failed, showing last data","noLive":"no live data","wd":["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]}' ;;
esac

stale=false
out=$(timeout 55 bash "$FETCH" 2>/dev/null)
if [ -n "$out" ] && jq -e . >/dev/null 2>&1 <<<"$out"; then
  printf '%s' "$out" > "$LAST"
else
  out=$(cat "$LAST" 2>/dev/null || true)
  stale=true
  if [ -z "$out" ]; then
    jq -cn --argjson S "$S" '{text: "cc", class: "stale", tooltip: $S.stale}'
    exit 0
  fi
fi

jq -c --arg mode "$mode" --argjson S "$S" --argjson now "$(date +%s)" --argjson stale "$stale" '
def epoch: if type == "number" then . / 1000
           else (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) end;
def fixed2: (. * 100 | round) as $c
  | (($c / 100) | floor | tostring) + "." + (($c % 100) | tostring | if length < 2 then "0" + . else . end);
def money: if . >= 100 then "$" + (round | tostring) else "$" + fixed2 end;
def pctstr: (. // 0) | round | tostring;
def left(e): ((e - $now) / 60 | floor | if . < 0 then 0 else . end) as $m
  | if $m >= 60 then "\($m / 60 | floor)h \($m % 60)m" else "\($m)m" end;
def when(e): (e | localtime) as $t
  | if (e - $now) < 86400 then ($t | strftime("%H:%M"))
    else $S.wd[($t | strftime("%w") | tonumber)] + " " + ($t | strftime("%H:%M")) end;
def sev(p): if p >= 95 then "critical" elif p >= 85 then "warning" else "normal" end;
def worst: [.live.weekly.pct // 0] + [.live.weekly_models[]?.pct // 0] | max;
def codexLabel(w): "Codex " + (if w.minutes >= 1440 then "\(w.minutes / 1440 | round)D" else "\(w.minutes / 60 | round)H" end);
def subsTotal: [.subscription.price // 0, .subscriptionOpenai.price // 0] | add;
def cur: .subscription.currency // "US$";
.live as $l
| (if $mode == "today" then (.totalToday // 0 | money)
   elif $mode == "weekly" then (if $l then "w " + (worst | pctstr) + "%" else "cc" end)
   elif $mode == "subs" then cur + (subsTotal | tostring)
   elif $mode == "reset" then (if $l then left($l.session.resets_at | epoch) else "cc" end)
   else (if $l then ($l.session.pct | pctstr) + "%"
         elif .block then (.block.costUSD // 0 | money) else "cc" end)
   end) as $text
| (if $mode == "weekly" then (if $l then sev(worst) else "normal" end)
   elif $mode == "session" or $mode == "reset" then (if $l then sev($l.session.pct) else "normal" end)
   else "normal" end) as $sev
| ([
    ((.totalMonth // 0 | money) + " " + $S.month + "  ·  " + (.totalToday // 0 | money) + " " + $S.today),
    (if $l then $S.session + " " + ($l.session.pct | pctstr) + "%  ·  " + $S.resets + " "
               + when($l.session.resets_at | epoch) + " (" + left($l.session.resets_at | epoch) + ")"
     else $S.noLive end),
    (if $l.weekly then $S.weeklyAll + " " + ($l.weekly.pct | pctstr) + "%  ·  " + $S.resets + " " + when($l.weekly.resets_at | epoch) else empty end),
    ($l.weekly_models[]? | (.model // "model") + " " + (.pct | pctstr) + "%  ·  " + $S.resets + " " + when(.resets_at | epoch)),
    ([.liveOpenai.primary, .liveOpenai.secondary] | .[] | select(.)
      | codexLabel(.) + " " + (.pct | pctstr) + "%  ·  " + $S.resets + " " + when(.resets_at | epoch)),
    (if .subscription or .subscriptionOpenai
     then $S.plan + ": " + ([.subscription, .subscriptionOpenai] | map(select(.) | .name + " " + .currency + (.price | tostring)) | join("  ·  "))
     else empty end),
    (if .block and .block.isActive
     then $S.block + ": " + (.block.costUSD // 0 | money)
          + (if .block.projection then "  →  ≈" + (.block.projection.totalCost | money) + " (" + (.block.projection.remainingMinutes | tostring) + "m " + $S.left + ")" else "" end)
     else empty end),
    (if $stale then $S.stale else empty end)
  ] | join("\n")) as $tip
| {text: $text, tooltip: $tip, class: (if $stale then "stale" else $sev end),
   percentage: (if $l then ($l.session.pct | round) else 0 end)}' <<<"$out"
