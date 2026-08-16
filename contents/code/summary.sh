#!/usr/bin/env bash
# Copyright (C) 2026 NventaTech — GPL-3.0-or-later
# cctop - morning cost summary as a desktop notification.
# Meant to run from a systemd user timer; reuses fetch.sh for all data.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"

j=$(bash "$DIR/fetch.sh") || exit 1
[ -z "$j" ] && exit 1

yesterday=$(jq -r '.spark[-2].c // 0' <<<"$j")
week=$(jq -r '[.spark[].c] | add // 0' <<<"$j")
pct=$(jq -r '[.live.weekly.pct // 0, (.live.weekly_models // [])[].pct] | max // empty' <<<"$j")

msg=$(LC_NUMERIC=C printf 'yesterday $%.2f · 7 days $%.2f' "$yesterday" "$week")
[ -n "$pct" ] && msg="$msg · weekly limit ${pct}%"

notify-send -a cctop -i office-chart-bar "cctop — morning summary" "$msg"
