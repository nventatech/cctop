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

out=$(HOME="$tmp/home" XDG_CACHE_HOME="$tmp/cache" bash "$DIR/../contents/code/fetch.sh")
check() {
  local got; got=$(jq -r ".providers[] | select(.id == \"$1\") | .costMonth" <<<"$out")
  if [ "$got" = "$2" ]; then echo "ok   $1 = $got"; else echo "FAIL $1: expected $2, got $got"; exit 1; fi
}
# gpt-5.4-mini: 1M in * 0.75 + 1M out * 4.5 = 5.25; no model -> gpt-5.4: 1M in * 2.5
check openai 7.75
# 1M input gemini-2.5-flash * 0.3 + 1M output gemini-2.5-pro * 10
check gemini 10.3
