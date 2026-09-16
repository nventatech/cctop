#!/usr/bin/env bash
# Runs fetch.sh against the synthetic Codex/Gemini logs in fixtures/home and
# checks the per-model pricing. Timestamps in the fixtures are rewritten to
# today so the month/day windows always include them.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp -r "$DIR/fixtures/home" "$tmp/home"
now=$(date -u +%Y-%m-%dT10:00:00Z)
nano=$(( $(date +%s) * 1000000000 ))
sed -i "s/\"timestamp\":\"[^\"]*\"/\"timestamp\":\"$now\"/" "$tmp"/home/.codex/sessions/2026/08/*.jsonl
sed -i "s/\"timeUnixNano\":\"[0-9]*\"/\"timeUnixNano\":\"$nano\"/g" "$tmp/home/.gemini/telemetry.log"
touch "$tmp"/home/.codex/sessions/2026/08/*.jsonl
epoch=$(date +%s)
sed -i "s/FUTURE_LONG/$(( epoch + 259140 ))/g; s/FUTURE_SHORT/$(( epoch + 3600 ))/g; s/PAST/$(( epoch - 60 ))/g" "$tmp/home/.codex/sessions/2026/08/rollout-default.jsonl"
touch "$tmp/home/.codex/sessions/2026/08/rollout-default.jsonl"

out=$(HOME="$tmp/home" XDG_CACHE_HOME="$tmp/cache" bash "$DIR/../shared/code/fetch.sh")
check() {
  local got; got=$(jq -r ".providers[] | select(.id == \"$1\") | .costMonth" <<<"$out")
  if [ "$got" = "$2" ]; then echo "ok   $1 = $got"; else echo "FAIL $1: expected $2, got $got"; exit 1; fi
}
# gpt-5.4-mini: 1M in * 0.75 + 1M out * 4.5 = 5.25; no model -> gpt-5.4: 1M in * 2.5
check openai 7.75
# 1M input gemini-2.5-flash * 0.3 + 1M output gemini-2.5-pro * 10
check gemini 10.3

checkq() {
  local got; got=$(jq -r "$1" <<<"$out")
  if [ "$got" = "$2" ]; then echo "ok   $1 = $got"; else echo "FAIL $1: expected $2, got $got"; exit 1; fi
}
checkq '.liveOpenai.primary.pct' 83
checkq '.liveOpenai.primary.minutes' 10080
checkq '.liveOpenai.secondary' null
checkq '(.liveOpenai.primary.resets_at / 1000 - '"$epoch"') | . >= 259110 and . <= 259170' true
checkq '.liveOpenai.primary.resets_at % 60000' 0

# pure notification helpers, read straight out of main.qml
node "$DIR/notify.js"

# pure helpers of the GNOME extension
node "$DIR/logic.mjs"
