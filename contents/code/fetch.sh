#!/usr/bin/env bash
# Copyright (C) 2026 NventaTech — GPL-3.0-or-later
# cctop - multi-provider AI cost collector.
# Everything is read locally, no account setup:
#   - Claude cost: local JSONL files via ccusage
#   - Claude session/weekly limits: usage endpoint with the OAuth token the
#     Claude Code CLI already keeps in ~/.claude/.credentials.json
#   - Subscription: rate limit tier stored in ~/.claude.json
#   - OpenAI (Codex CLI) and Gemini (Gemini CLI): local log readers below,
#     dormant until the CLI is installed — provider only shows up when its
#     directory exists and has parseable usage data
export PATH="$HOME/.bun/bin:/usr/local/bin:/usr/bin:$PATH"
CREDS="$HOME/.claude/.credentials.json"
CLAUDE_CFG="$HOME/.claude.json"

# ccusage runner: bun if available, plain node otherwise
if command -v bunx >/dev/null 2>&1; then CCU="bunx ccusage"; else CCU="npx -y ccusage"; fi

# cached <name> <ttl-seconds> <command...> — every ccusage run reparses all
# JSONL logs (~1s CPU), so slow-moving data is reused from tmpfs for its TTL
CACHE_DIR="${XDG_RUNTIME_DIR:-/tmp}/cctop-cache"
mkdir -p "$CACHE_DIR"
cached() {
  local f="$CACHE_DIR/$1.json" ttl="$2" age=999999 out; shift 2
  [ -s "$f" ] && age=$(( $(date +%s) - $(stat -c %Y "$f") ))
  if [ "$age" -lt "$ttl" ]; then cat "$f"; return; fi
  out=$("$@" 2>/dev/null)
  if [ -n "$out" ]; then printf '%s' "$out" > "$f"; printf '%s' "$out"
  else [ -s "$f" ] && cat "$f"; fi
}

# ----------------- date windows (current month + last 7 days) -----------------
since=$(date +%Y%m01)
today=$(date +%Y-%m-%d)
monthStart=$(date +%Y-%m-01)
week=$(date -d '6 days ago' +%Y%m%d)
fetchSince=$(printf '%s\n%s\n' "$since" "$week" | sort | head -1)
days=$(for i in 6 5 4 3 2 1 0; do date -d "-$i days" +%Y-%m-%d; done | jq -Rc . | jq -cs .)

# ----------------- claude cost (local logs) -----------------
daily=$($CCU daily --json --since "$fetchSince" 2>/dev/null)
[ -z "$daily" ] && daily='{}'
block=$($CCU blocks --active --json 2>/dev/null)
[ -z "$block" ] && block='{}'
claude=$(jq -cn --argjson d "$daily" --arg today "$today" --arg ms "$monthStart" '{
  id: "claude", name: "Claude", color: "#e8a33d",
  costMonth: ((($d.daily // []) | map(select(.period >= $ms) | .totalCost) | add) // 0),
  today: (($d.daily // []) | map(select(.period == $today)) | (.[0].totalCost // 0))
}')

# last 7 days, zero-filled (claude only — other providers are marginal here)
spark=$(jq -cn --argjson d "$daily" --argjson days "$days" \
  '[ $days[] as $day | {d: $day, c: ((($d.daily // []) | map(select(.period == $day) | .totalCost) | add) // 0)} ]')

# ----------------- claude live limits (local OAuth token) -----------------
# The endpoint rate-limits aggressive polling (HTTP 429), so successful
# responses are cached for 4 min and reused — including as fallback when a
# request fails. Costs keep refreshing every cycle; limits move slowly.
live='null'
DBG="${XDG_RUNTIME_DIR:-/tmp}/cctop-debug.log"
CACHE="${XDG_RUNTIME_DIR:-/tmp}/cctop-live.json"
cacheAge=999999
[ -s "$CACHE" ] && cacheAge=$(( $(date +%s) - $(stat -c %Y "$CACHE") ))
if [ "$cacheAge" -lt 240 ]; then
  live=$(cat "$CACHE")
else
  tok=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDS" 2>/dev/null)
  if [ -n "$tok" ]; then
    resp=$(curl -s --max-time 15 -w '\n%{http_code}' "https://api.anthropic.com/api/oauth/usage" \
      -H "Authorization: Bearer $tok" \
      -H "anthropic-beta: oauth-2025-04-20" \
      -H "Content-Type: application/json" 2>/dev/null)
    rc=$?
    http=${resp##*$'\n'}
    resp=${resp%$'\n'*}
    [ "$http" != "200" ] && resp=""
    echo "$(date '+%F %T') curl_rc=$rc http=$http resp_len=${#resp}" >> "$DBG"
    [ "$(wc -l < "$DBG" 2>/dev/null || echo 0)" -gt 200 ] && { tail -n 100 "$DBG" > "$DBG.t" && mv "$DBG.t" "$DBG"; }
    if [ -n "$resp" ]; then
      live=$(jq -c '{
        session: {pct: (.five_hour.utilization // 0), resets_at: .five_hour.resets_at},
        weekly:  {pct: (.seven_day.utilization // 0), resets_at: .seven_day.resets_at},
        weekly_model: ((.limits // []) | map(select(.kind == "weekly_scoped")) | (.[0] // null)
                      | if . then {pct: .percent, resets_at: .resets_at} else null end)
      }' <<<"$resp" 2>/dev/null) || live='null'
      [ "$live" != "null" ] && [ -n "$live" ] && printf '%s' "$live" > "$CACHE"
    fi
  fi
  # request failed: reuse the last good limits instead of dropping them
  [ "${live:-null}" = "null" ] && [ -s "$CACHE" ] && live=$(cat "$CACHE")
fi
[ -z "$live" ] && live='null'

# ----------------- subscription (local Claude Code config) -----------------
sub='null'
tier=$(jq -r '.oauthAccount.organizationRateLimitTier // empty' "$CLAUDE_CFG" 2>/dev/null)
case "$tier" in
  *max_20x*) sub='{"name":"Claude Max 20x","price":200,"currency":"US$"}' ;;
  *max_5x*)  sub='{"name":"Claude Max 5x","price":100,"currency":"US$"}' ;;
  *pro*)     sub='{"name":"Claude Pro","price":20,"currency":"US$"}' ;;
esac

# ----------------- chatgpt subscription (Codex CLI local login) -----------------
# The Codex CLI keeps the OpenAI id_token (JWT) in ~/.codex/auth.json when
# logged in with a ChatGPT account; its payload carries chatgpt_plan_type.
# Decoded locally (base64), nothing leaves the machine.
subOa='null'
CODEX_AUTH="$HOME/.codex/auth.json"
if [ -s "$CODEX_AUTH" ]; then
  payload=$(jq -r '.tokens.id_token // empty' "$CODEX_AUTH" 2>/dev/null | cut -d. -f2 | tr '_-' '/+')
  while [ -n "$payload" ] && [ $(( ${#payload} % 4 )) -ne 0 ]; do payload="$payload="; done
  plan=$(printf '%s' "$payload" | base64 -d 2>/dev/null \
    | jq -r '."https://api.openai.com/auth".chatgpt_plan_type // empty' 2>/dev/null)
  case "$plan" in
    pro)      subOa='{"name":"ChatGPT Pro","price":200,"currency":"US$"}' ;;
    plus)     subOa='{"name":"ChatGPT Plus","price":20,"currency":"US$"}' ;;
    team)     subOa='{"name":"ChatGPT Team","price":25,"currency":"US$"}' ;;
    business) subOa='{"name":"ChatGPT Business","price":25,"currency":"US$"}' ;;
  esac
fi

# ----------------- openai (Codex CLI local session logs) -----------------
# ~/.codex/sessions/**/rollout-*.jsonl: one token_count event per turn with
# last_token_usage {input_tokens, cached_input_tokens, output_tokens}.
# Pricing: gpt-5 family list price (in 1.25, cached 0.125, out 10.00 per M).
codex_cost() {
  find "$HOME/.codex/sessions" -name 'rollout-*.jsonl' "$@" 2>/dev/null \
    | xargs -r cat 2>/dev/null \
    | jq -s '
      [ .[] | select(.type == "event_msg" and .payload.type == "token_count")
            | .payload.info.last_token_usage | select(.) ] as $ev
      | (($ev | map(.input_tokens // 0) | add // 0) -
         ($ev | map(.cached_input_tokens // 0) | add // 0)) as $in
      | ($ev | map(.cached_input_tokens // 0) | add // 0) as $cached
      | ($ev | map(.output_tokens // 0) | add // 0) as $out
      | ($in * 1.25 + $cached * 0.125 + $out * 10) / 1000000'
}
openai='null'
if [ -d "$HOME/.codex/sessions" ]; then
  cm=$(codex_cost -newermt "$(date +%Y-%m-01)"); ctd=$(codex_cost -newermt "$today")
  if [ -n "$cm" ] && [ "$cm" != "0" ]; then
    openai=$(jq -cn --argjson c "$cm" --argjson t "${ctd:-0}" \
      '{id: "openai", name: "OpenAI", color: "#10a37f", costMonth: $c, today: $t}')
  fi
fi

# ----------------- gemini (Gemini CLI local telemetry) -----------------
# Needs telemetry enabled in the CLI (~/.gemini/telemetry.log, OTLP JSON
# lines). Token counts come as gemini_cli.token.usage data points with a
# token_type attribute. Pricing: gemini-2.5-pro list price (in 1.25, out 10 per M).
gemini='null'
if [ -s "$HOME/.gemini/telemetry.log" ]; then
  g=$(jq -s --arg today "$today" '
    [ .[] | .. | objects | select(.name? == "gemini_cli.token.usage") | .dataPoints? // [] | .[] ] as $pts
    | def total(f): [$pts[] | select(f) | (.asInt // .value // 0)] | add // 0;
      { inp: total(.attributes?[]?.value?.stringValue == "input"),
        out: total(.attributes?[]?.value?.stringValue == "output") }
    | (.inp * 1.25 + .out * 10) / 1000000' "$HOME/.gemini/telemetry.log" 2>/dev/null)
  if [ -n "$g" ] && [ "$g" != "0" ] && [ "$g" != "null" ]; then
    gemini=$(jq -cn --argjson c "$g" \
      '{id: "gemini", name: "Gemini", color: "#4285f4", costMonth: $c, today: 0}')
  fi
fi

# ----------------- top projects this month -----------------
# per-day costs keyed by flattened project path; worktree sessions fold into
# their parent project, label is the last dash segment of the path
projects=$(cached "projects-$since" 900 $CCU claude daily --json --instances --since "$since" | jq -c --arg ms "$monthStart" '
  [ (.projects // {}) | to_entries[]
    | {p: (.key | sub("--claude-worktrees-.*$"; "") | split("-") | last),
       c: ([.value[] | select(.date >= $ms) | .totalCost] | add // 0)} ]
  | group_by(.p) | map({name: .[0].p, cost: (map(.c) | add)})
  | sort_by(-.cost) | .[0:3]')
[ -z "$projects" ] && projects='[]'

# ----------------- cost by model this month (from the daily payload) -----------------
models=$(jq -cn --argjson d "$daily" --arg ms "$monthStart" '
  [ ($d.daily // [])[] | select(.period >= $ms) | (.modelBreakdowns // [])[]
    | {name: .modelName, cost: .cost} ]
  | group_by(.name) | map({name: .[0].name, cost: (map(.cost) | add)})
  | sort_by(-.cost) | .[0:4]')
[ -z "$models" ] && models='[]'

# ----------------- previous month total (hero comparison) -----------------
# anchor on day 1 before subtracting: 'last month' on the 29th-31st can
# normalize into the current month (Jul 31 - 1 month = Jun 31 = Jul 1)
prevSince=$(date -d "$monthStart -1 month" +%Y%m01)
prevKey=$(date -d "$monthStart -1 month" +%Y-%m)
prevMonth=$(cached "monthly-$prevKey" 43200 $CCU monthly --json --since "$prevSince" | jq -c --arg m "$prevKey" \
  '[(.monthly // [])[] | select((.month // .period) == $m) | .totalCost] | (add // 0)')
[ -z "$prevMonth" ] && prevMonth=0

# ----------------- monthly history (last 6 months) -----------------
# current month lags up to the TTL here; the UI overwrites the last bar with
# the live month total so it always matches the hero number
sixSince=$(date -d "$monthStart -5 months" +%Y%m01)
months=$(cached "months-$(date +%Y-%m)" 3600 $CCU monthly --json --since "$sixSince" | jq -c '
  [ (.monthly // [])[] | {m: (.month // .period), c: .totalCost} ] | sort_by(.m) | .[-6:]')
[ -z "$months" ] && months='[]'

# ----------------- session history (local logs) -----------------
hist=$(cached history 300 $CCU session --json | jq -c '
  [ (.session // []) | sort_by(.metadata.lastActivity) | reverse | .[0:8][]
    | { last: .metadata.lastActivity, cost: .totalCost, models: (.modelsUsed // []) } ]')
[ -z "$hist" ] && hist='[]'

# ----------------- output -----------------
jq -cn --argjson c "$claude" --argjson oa "$openai" --argjson ge "$gemini" \
      --argjson b "$block" --argjson live "$live" --argjson sub "$sub" \
      --argjson subOa "$subOa" --argjson h "$hist" --argjson sp "$spark" \
      --argjson pr "$projects" --argjson pm "$prevMonth" --argjson mo "$models" \
      --argjson mh "$months" '
  ([$c] + [$oa, $ge | select(. != null)]) as $ps | {
    providers: $ps,
    totalMonth: ($ps | map(.costMonth) | add),
    totalToday: ($ps | map(.today // 0) | add),
    block: (($b.blocks // []) | .[0] // null),
    sessionModels: (($b.blocks // []) | (.[0].models // [])),
    live: $live,
    subscription: $sub,
    subscriptionOpenai: $subOa,
    history: $h,
    spark: $sp,
    projects: $pr,
    prevMonth: $pm,
    models: $mo,
    months: $mh
  }'
