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

if command -v ccusage >/dev/null 2>&1; then CCU="ccusage"
elif command -v bunx >/dev/null 2>&1; then CCU="bunx ccusage"
else CCU="npx -y ccusage"; fi

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cctop"
mkdir -p "$CACHE_DIR"
find "$CACHE_DIR" -type f -mtime +60 -delete 2>/dev/null
cached() {
  local f="$CACHE_DIR/$1.json" ttl="$2" age=999999 out; shift 2
  [ -s "$f" ] && age=$(( $(date +%s) - $(stat -c %Y "$f") ))
  if [ "$age" -lt "$ttl" ]; then cat "$f"; return; fi
  out=$("$@" 2>/dev/null)
  if [ -n "$out" ]; then printf '%s' "$out" > "$f"; printf '%s' "$out"
  else [ -s "$f" ] && cat "$f"; fi
}

since=$(date +%Y%m01)
today=$(date +%Y-%m-%d)
monthStart=$(date +%Y-%m-01)
week=$(date -d '6 days ago' +%Y%m%d)
weekStart=$(date -d '6 days ago' +%Y-%m-%d)
d30=$(date -d '29 days ago' +%Y%m%d)
d30Start=$(date -d '29 days ago' +%Y-%m-%d)
fetchSince=$(printf '%s\n%s\n' "$since" "$d30" | sort | head -1)
days=$(for i in 6 5 4 3 2 1 0; do date -d "-$i days" +%Y-%m-%d; done | jq -Rc . | jq -cs .)

tmpD=$(mktemp); tmpB=$(mktemp)
cached "daily-$fetchSince" 120 $CCU daily --json --since "$fetchSince" > "$tmpD" &
cached blocks 20 $CCU blocks --active --json > "$tmpB" &
wait
daily=$(cat "$tmpD"); block=$(cat "$tmpB"); rm -f "$tmpD" "$tmpB"
[ -z "$daily" ] && daily='{}'
[ -z "$block" ] && block='{}'
claude=$(jq -cn --argjson d "$daily" --arg today "$today" --arg ms "$monthStart" \
  --arg ws "$weekStart" --arg ds "$d30Start" '
  def sumFrom($from): (($d.daily // []) | map(select(.period >= $from) | .totalCost) | add) // 0;
  { id: "claude", name: "Claude", color: "#e8a33d",
    costMonth: sumFrom($ms), d7: sumFrom($ws), d30: sumFrom($ds),
    today: (($d.daily // []) | map(select(.period == $today)) | (.[0].totalCost // 0)) }')

spark=$(jq -cn --argjson d "$daily" --argjson days "$days" \
  '[ $days[] as $day | {d: $day, c: ((($d.daily // []) | map(select(.period == $day) | .totalCost) | add) // 0)} ]')

live='null'
DBG="$CACHE_DIR/debug.log"
CACHE="$CACHE_DIR/live-v3.json"
cacheAge=999999
[ -s "$CACHE" ] && cacheAge=$(( $(date +%s) - $(stat -c %Y "$CACHE") ))
liveTtl=240
if [ -s "$CACHE" ] && jq -e '[.session.pct, .weekly.pct, (.weekly_models // [])[].pct]
    | max >= 90' "$CACHE" >/dev/null 2>&1; then liveTtl=60; fi
if [ "$cacheAge" -lt "$liveTtl" ]; then
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
    if [ "${CCTOP_DEBUG:-0}" = "1" ]; then
      echo "$(date '+%F %T') curl_rc=$rc http=$http resp_len=${#resp}" >> "$DBG"
      [ "$(wc -l < "$DBG" 2>/dev/null || echo 0)" -gt 200 ] && { tail -n 100 "$DBG" > "$DBG.t" && mv "$DBG.t" "$DBG"; }
    fi
    if [ -n "$resp" ]; then
      live=$(jq -c '
        (.limits // []) as $l
        | def lim(k): ($l | map(select(.kind == k)) | .[0] // null);
          def flags(x): {active: (x.is_active // false), severity: (x.severity // "normal")};
        {
          session: ({pct: (.five_hour.utilization // 0), resets_at: .five_hour.resets_at,
                     locked: (.five_hour.locked_reason // null)}
                    + flags(lim("session"))),
          weekly:  ({pct: (.seven_day.utilization // 0), resets_at: .seven_day.resets_at,
                     locked: (.seven_day.locked_reason // null)}
                    + flags(lim("weekly_all"))),
          weekly_models: [ $l[] | select(.kind == "weekly_scoped")
                           | {pct: .percent, resets_at: .resets_at,
                              model: (.scope.model.display_name // null)} + flags(.) ],
          extra: (.extra_usage | if (.is_enabled // false) then
                    {pct: (.utilization // 0), limit: .monthly_limit,
                     used: .used_credits, currency: (.currency // "US$")}
                  else null end),
          spend: (.spend | if (.enabled // false) then
                    (.limit // null) as $lim
                    | {pct: (.percent // 0),
                       used: ((.used.amount_minor // 0) / pow(10; (.used.exponent // 2))),
                       limit: (if $lim then ($lim.amount_minor // 0) / pow(10; ($lim.exponent // 2))
                               else null end),
                       currency: (.used.currency // "USD")}
                  else null end)
        }' <<<"$resp" 2>/dev/null) || live='null'
      [ "$live" != "null" ] && [ -n "$live" ] && printf '%s' "$live" > "$CACHE"
    fi
  fi
  [ "${live:-null}" = "null" ] && [ -s "$CACHE" ] && live=$(cat "$CACHE")
fi
[ -z "$live" ] && live='null'

sub='null'
# seatTier is needed for team accounts: their rate limit tier is an opaque
# codename (e.g. default_raven) that carries no plan name at all.
tier=$(jq -r '[.oauthAccount.organizationRateLimitTier, .oauthAccount.seatTier]
              | map(select(.)) | join(" ")' "$CLAUDE_CFG" 2>/dev/null)
case "$tier" in
  *max_20x*)   sub='{"name":"Claude Max 20x","price":200,"currency":"US$"}' ;;
  *max_5x*)    sub='{"name":"Claude Max 5x","price":100,"currency":"US$"}' ;;
  *team_tier*) sub='{"name":"Claude Team","price":25,"currency":"US$"}' ;;
  *pro*)       sub='{"name":"Claude Pro","price":20,"currency":"US$"}' ;;
esac

subOa='null'
CODEX_AUTH="$HOME/.codex/auth.json"
if [ -s "$CODEX_AUTH" ]; then
  payload=$(jq -r '.tokens.id_token // empty' "$CODEX_AUTH" 2>/dev/null | cut -d. -f2 | tr '_-' '/+')
  while [ -n "$payload" ] && [ $(( ${#payload} % 4 )) -ne 0 ]; do payload="$payload="; done
  plan=$(printf '%s' "$payload" | base64 -d 2>/dev/null \
    | jq -r '."https://api.openai.com/auth".chatgpt_plan_type // empty' 2>/dev/null)
  # newer plans report a compound plan_type (e.g. self_serve_business_prolite),
  # so glob-match — business/team first, since those strings can contain "pro"
  case "$plan" in
    *business*) subOa='{"name":"ChatGPT Business","price":25,"currency":"US$"}' ;;
    *team*)     subOa='{"name":"ChatGPT Team","price":25,"currency":"US$"}' ;;
    *pro*)      subOa='{"name":"ChatGPT Pro","price":200,"currency":"US$"}' ;;
    *plus*)     subOa='{"name":"ChatGPT Plus","price":20,"currency":"US$"}' ;;
  esac
fi

CODEX_PRICES='{
  "gpt-5.6": [5, 0.5, 30], "gpt-5.6-sol": [5, 0.5, 30], "gpt-5.6-terra": [2.5, 0.25, 15],
  "gpt-5.6-luna": [1, 0.1, 6], "gpt-5.5": [5, 0.5, 30], "gpt-5.5-pro": [30, 3, 180],
  "gpt-5.4": [2.5, 0.25, 15], "gpt-5.4-mini": [0.75, 0.075, 4.5], "gpt-5.4-nano": [0.2, 0.02, 1.25],
  "gpt-5.4-pro": [30, 3, 180], "gpt-5.3-codex": [1.75, 0.175, 14],
  "gpt-5": [1.25, 0.125, 10], "gpt-5-codex": [1.25, 0.125, 10],
  "gpt-5-mini": [0.25, 0.025, 2], "gpt-5-nano": [0.05, 0.005, 0.4],
  "gpt-4o": [2.5, 0.25, 10], "gpt-4o-mini": [0.15, 0.015, 0.6],
  "gpt-4.1": [2, 0.5, 8], "gpt-4.1-mini": [0.4, 0.1, 1.6],
  "o3": [10, 1, 40], "o3-mini": [1.1, 0.11, 4.4], "o4-mini": [1.1, 0.275, 4.4]
}'
codex_cost() {
  local f total=0 c
  while IFS= read -r f; do
    c=$(jq -s --arg from "$1" --argjson prices "$CODEX_PRICES" '
      ([ .[] | select(.type == "turn_context" or .type == "session_meta")
             | .payload.model // empty ] | last // "gpt-5.4") as $model
      | ($model | sub("-[0-9]{4}-[0-9]{2}-[0-9]{2}$"; "")) as $base
      | ($prices[$model] // $prices[$base]
         // ([ $prices | keys[] | select($base | startswith(.)) ] | sort_by(-length) | .[0] | if . then $prices[.] else null end)
         // $prices["gpt-5.4"]) as $p
      | [ .[] | select(.type == "event_msg" and .payload.type == "token_count")
            | select((.timestamp // $from) >= $from)
            | .payload.info.last_token_usage | select(.) ] as $ev
      | (($ev | map(.input_tokens // 0) | add // 0) -
         ($ev | map(.cached_input_tokens // 0) | add // 0)) as $in
      | ($ev | map(.cached_input_tokens // 0) | add // 0) as $cached
      | ($ev | map(.output_tokens // 0) | add // 0) as $out
      | ($in * $p[0] + $cached * $p[1] + $out * $p[2]) / 1000000' "$f" 2>/dev/null)
    total=$(jq -n --argjson a "$total" --argjson b "${c:-0}" '$a + $b')
  done < <(find "$HOME/.codex/sessions" -name 'rollout-*.jsonl' -newermt "$1" 2>/dev/null)
  echo "$total"
}
openai='null'
if [ -d "$HOME/.codex/sessions" ]; then
  cm=$(codex_cost "$monthStart"); ctd=$(codex_cost "$today")
  c7=$(codex_cost "$weekStart"); c30=$(codex_cost "$d30Start")
  if [ -n "$cm" ] && [ "$cm" != "0" ]; then
    openai=$(jq -cn --argjson c "$cm" --argjson t "${ctd:-0}" --argjson w "${c7:-0}" --argjson m "${c30:-0}" \
      '{id: "openai", name: "OpenAI", color: "#10a37f", costMonth: $c, today: $t, d7: $w, d30: $m}')
  fi
fi

# Codex stamps its own quota into every token_count event it logs:
# rate_limits.primary/secondary {used_percent, window_minutes, resets_at (epoch s)}.
# Newest logged value wins; a window whose reset has already passed is dropped,
# since the quota refilled and the logged percentage means nothing any more.
# Needs no request — codex writes it down locally — with the tradeoff that it
# only refreshes when codex actually runs.
liveOa='null'
if [ -d "$HOME/.codex/sessions" ]; then
  liveOa=$(find "$HOME/.codex/sessions" -name 'rollout-*.jsonl' -newermt '9 days ago' \
      -printf '%T@ %p\n' 2>/dev/null | sort -n | cut -d' ' -f2- \
    | xargs -r grep -h '"rate_limits":{' 2>/dev/null | tail -n 50 \
    | jq -s --argjson now "$(date +%s)" '
        def win(l): if (l and l.resets_at > $now)
                    then { pct: (l.used_percent // 0 | floor),
                           resets_at: (l.resets_at * 1000),
                           minutes: (l.window_minutes // 0) }
                    else null end;
        [ .[] | select(.payload.type == "token_count") | .payload.rate_limits | select(.) ]
        | last
        | if . then {primary: win(.primary), secondary: win(.secondary)}
               | select(.primary or .secondary)
          else empty end' 2>/dev/null)
  [ -z "$liveOa" ] && liveOa='null'
fi

GEMINI_PRICES='{
  "gemini-2.5-pro": [1.25, 10], "gemini-2.5-flash": [0.3, 2.5],
  "gemini-2.5-flash-lite": [0.1, 0.4], "gemini-2.0-flash": [0.1, 0.4],
  "gemini-2.0-flash-exp": [0.075, 0.3], "gemini-1.5-pro": [1.25, 5], "gemini-1.5-flash": [0.075, 0.3]
}'
gemini='null'
if [ -s "$HOME/.gemini/telemetry.log" ]; then
  monthNano=$(( $(date -d "$monthStart" +%s) * 1000000000 ))
  dayNano=$(( $(date -d "$today" +%s) * 1000000000 ))
  weekNano=$(( $(date -d "$weekStart" +%s) * 1000000000 ))
  d30Nano=$(( $(date -d "$d30Start" +%s) * 1000000000 ))
  g=$(jq -s --argjson mn "$monthNano" --argjson dn "$dayNano" --argjson wn "$weekNano" --argjson tn "$d30Nano" --argjson prices "$GEMINI_PRICES" '
    [ .[] | .. | objects | select(.name? == "gemini_cli.token.usage")
          | .. | objects | select(has("dataPoints")) | .dataPoints[] ] as $pts
    | def attr($k): [ .attributes[]? | select(.key == $k) | .value.stringValue ] | first // "";
      def since($t): [ $pts[] | select(((.timeUnixNano // .startTimeUnixNano // "0") | tonumber) >= $t) ];
      def rate: ($prices[attr("model")] // $prices["gemini-2.5-pro"]);
      def cost($p): ([ $p[] | ((.asInt // .value // 0) | tonumber) as $n
                       | if attr("token_type") == "input" then $n * rate[0]
                         elif attr("token_type") == "output" then $n * rate[1] else 0 end ]
                     | add // 0) / 1000000;
      { month: cost(since($mn)), today: cost(since($dn)), d7: cost(since($wn)), d30: cost(since($tn)) }' \
    "$HOME/.gemini/telemetry.log" 2>/dev/null)
  if [ -n "$g" ] && [ "$(jq -r '.month // 0' <<<"$g" 2>/dev/null)" != "0" ]; then
    gemini=$(jq -cn --argjson g "$g" \
      '{id: "gemini", name: "Gemini", color: "#4285f4", costMonth: $g.month, today: $g.today, d7: $g.d7, d30: $g.d30}')
  fi
fi

homeKey=$(printf '%s' "$HOME" | tr '/.' '--')
projects=$(cached "projects-$since" 900 $CCU claude daily --json --instances --since "$since" | jq -c --arg ms "$monthStart" --arg home "$homeKey" '
  def projName: sub("--claude-worktrees-.*$"; "")
    | (if startswith($home) then .[($home | length):] else . end)
    | split("-") | map(select(. != "")) | .[-2:] | join("/")
    | if . == "" then "~" else . end;
  [ (.projects // {}) | to_entries[]
    | {p: (.key | projName),
       c: ([.value[] | select(.date >= $ms) | .totalCost] | add // 0)} ]
  | group_by(.p) | map({name: .[0].p, cost: (map(.c) | add)})
  | sort_by(-.cost) | .[0:3]')
[ -z "$projects" ] && projects='[]'

models=$(jq -cn --argjson d "$daily" --arg ms "$monthStart" '
  [ ($d.daily // [])[] | select(.period >= $ms) | (.modelBreakdowns // [])[]
    | {name: .modelName, cost: .cost} ]
  | group_by(.name) | map({name: .[0].name, cost: (map(.cost) | add)})
  | sort_by(-.cost) | .[0:4]')
[ -z "$models" ] && models='[]'

prevSince=$(date -d "$monthStart -1 month" +%Y%m01)
prevKey=$(date -d "$monthStart -1 month" +%Y-%m)
prevMonth=$(cached "monthly-$prevKey" 43200 $CCU monthly --json --since "$prevSince" | jq -c --arg m "$prevKey" \
  '[(.monthly // [])[] | select((.month // .period) == $m) | .totalCost] | (add // 0)')
[ -z "$prevMonth" ] && prevMonth=0

sixSince=$(date -d "$monthStart -5 months" +%Y%m01)
months=$(cached "months-$(date +%Y-%m)" 3600 $CCU monthly --json --since "$sixSince" | jq -c '
  [ (.monthly // [])[] | {m: (.month // .period), c: .totalCost} ] | sort_by(.m) | .[-6:]')
[ -z "$months" ] && months='[]'

hist=$(cached history 300 $CCU session --json | jq -c '
  [ (.session // []) | sort_by(.metadata.lastActivity) | reverse | .[0:8][]
    | { last: .metadata.lastActivity, cost: .totalCost, models: (.modelsUsed // []) } ]')
[ -z "$hist" ] && hist='[]'

jq -cn --argjson c "$claude" --argjson oa "$openai" --argjson ge "$gemini" \
      --argjson b "$block" --argjson live "$live" --argjson sub "$sub" \
      --argjson liveOa "$liveOa" \
      --argjson subOa "$subOa" --argjson h "$hist" --argjson sp "$spark" \
      --argjson pr "$projects" --argjson pm "$prevMonth" --argjson mo "$models" \
      --argjson mh "$months" '
  ([$c] + [$oa, $ge | select(. != null)]) as $ps | {
    providers: $ps,
    totalMonth: ($ps | map(.costMonth) | add),
    totalToday: ($ps | map(.today // 0) | add),
    total7d: ($ps | map(.d7 // 0) | add),
    total30d: ($ps | map(.d30 // 0) | add),
    block: (($b.blocks // []) | .[0] // null),
    sessionModels: (($b.blocks // []) | (.[0].models // [])),
    live: $live,
    liveOpenai: $liveOa,
    subscription: $sub,
    subscriptionOpenai: $subOa,
    history: $h,
    spark: $sp,
    projects: $pr,
    prevMonth: $pm,
    models: $mo,
    months: $mh
  }'
