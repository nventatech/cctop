#!/usr/bin/env bash
# Copyright (C) 2026 NventaTech — GPL-3.0-or-later
# cctop - writes the last 30 days of Claude usage (per day and model) as CSV
# to the home directory and reports the path with a desktop notification.
set -u
export PATH="$HOME/.bun/bin:/usr/local/bin:/usr/bin:$PATH"
if command -v ccusage >/dev/null 2>&1; then CCU="ccusage"
elif command -v bunx >/dev/null 2>&1; then CCU="bunx ccusage"
else CCU="npx -y ccusage"; fi

out="$HOME/cctop-$(date +%F).csv"
since=$(date -d '29 days ago' +%Y%m%d)
if $CCU daily --json --since "$since" 2>/dev/null | jq -r '
    ["date", "model", "input_tokens", "output_tokens", "cache_create_tokens", "cache_read_tokens", "cost_usd"],
    (.daily[] | .period as $d | (.modelBreakdowns // [])[]
      | [$d, .modelName, .inputTokens, .outputTokens, .cacheCreationTokens, .cacheReadTokens, .cost])
    | @csv' > "$out" && [ -s "$out" ]; then
  notify-send -a cctop -i document-export cctop "CSV: $out"
else
  rm -f "$out"
  notify-send -a cctop -i dialog-error cctop "CSV export failed"
fi
