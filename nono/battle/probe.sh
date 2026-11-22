#!/usr/bin/env bash
# Runs the checks from docs/unverified-probes.md that need no human, on the Mac
# and inside the agent sandbox, and prints PASS, FAIL or SKIP for each probe ID.
#
#   mise -C ~/dotfiles run nono:probe
#
# NONO_PROBE_PROFILE picks the profile (default liflig-agent, the one Claude
# runs in). Sandboxed checks work in a throwaway repo under the first workspace
# root (~/CX, ...), never in a real one. A denial that fails can leave an empty
# file or directory behind; the summary names it. Exits 1 when any check fails.
#
# One check makes a Context7 call when CONTEXT7_API_KEY is set inside nono, and
# D4 makes one from the host when it is set here.
set -u
here=$(cd "$(dirname "$0")" && pwd -P)
dotfiles=$(cd "$here/../.." && pwd -P)
profile=${NONO_PROBE_PROFILE:-liflig-agent}
tag=$$-$RANDOM
green=$'\e[32m' red=$'\e[31m' yellow=$'\e[33m' dim=$'\e[2m' off=$'\e[0m'

lines=()
emit() { lines+=("$(printf '%s\t%s\t%s\t%s' "$1" "$2" "$3" "${4:-}")"); }

# P0: the profile, custom Seatbelt rules included, loads.
if out=$(nono profile show "$profile" 2>&1); then
  emit PASS P0 "profile $profile loads"
else
  emit FAIL P0 "profile $profile loads" "${out##*$'\n'}"
  printf '%s\n' "$out" >&2
  exit 1
fi

# E1: the Exa gate's LaunchAgent runs and refuses unknown paths.
if launchctl print "gui/$(id -u)/com.jonasws.nono-exa-gate" 2>/dev/null | grep -q 'state = running'; then
  emit PASS E1 'Exa gate LaunchAgent running'
else
  emit FAIL E1 'Exa gate LaunchAgent running' 'run: mise run sync:nono-exa-gate'
fi

# D4: Context7's response headers, for the cache design. Informational.
if [[ -n ${CONTEXT7_API_KEY:-} ]]; then
  headers=$(curl -sSG -D - -o /dev/null --max-time 30 https://context7.com/api/v2/libs/search \
    -H "Authorization: Bearer $CONTEXT7_API_KEY" --data-urlencode libraryName=mise 2>&1 |
    grep -iE '^(HTTP/|cache-control|etag|last-modified|ratelimit-)' | tr -d '\r' | paste -sd ';' -)
  emit INFO D4 'Context7 200 headers' "$headers"
else
  emit SKIP D4 'Context7 200 headers' 'CONTEXT7_API_KEY is not set on the host'
fi

# D5: curl supports %header{} (7.84+), which context7.sh relies on.
curl_version=$(curl --version | awk 'NR==1 {print $2}')
if printf '%s\n%s\n' 7.84.0 "$curl_version" | sort -V -C; then
  emit PASS D5 "curl $curl_version has %header{}"
else
  emit FAIL D5 "curl $curl_version has %header{}" 'context7.sh needs curl 7.84 or later'
fi

# The throwaway repo the sandboxed checks work in.
root=
for candidate in CX CNOPS CN-TERMINAL LIFLIG NSBNO; do
  [[ -d $HOME/$candidate ]] && { root=$HOME/$candidate; break; }
done
if [[ -z $root ]]; then
  echo 'probe: no workspace root (~/CX, ~/CNOPS, ...) to put the probe repo in' >&2
  exit 1
fi
repo=$root/.nono-probe-$tag
git init -q "$repo"
mkdir -p "$repo/.claude" "$repo/sub"
printf '{}\n' >"$repo/.mcp.json"
printf '{}\n' >"$repo/.claude/settings.json"
: >"$repo/mise.local.toml"
printf 'SECRET=nono-probe\n' >"$repo/.env"
printf 'SECRET=nono-probe\n' >"$repo/sub/.env.local"
printf 'SECRET=\n' >"$repo/.env.example"

inside=$(nono run --silent --profile "$profile" -- bash "$here/probe-inside.sh" "$repo" "$tag" 2>&1)
ran=0
while IFS= read -r line; do
  if [[ $line =~ ^(PASS|FAIL|SKIP)$'\t' ]]; then
    lines+=("$line")
    ((ran++))
  fi
done <<<"$inside"
if (( ran == 0 )); then
  emit FAIL -- 'sandboxed checks ran' "${inside##*$'\n'}"
fi

# S5: the launchctl job, had it been accepted, would have created this file.
sleep 2
if [[ -e /tmp/nono-escaped-$tag ]]; then
  emit FAIL S5 'nothing ran outside the sandbox' "/tmp/nono-escaped-$tag exists"
  launchctl remove "nono.probe.$tag" 2>/dev/null
else
  emit PASS S5 'nothing ran outside the sandbox'
fi

# H2 on the host: what mise tasks and #!/usr/bin/env bash scripts get.
host_bash=$(command -v bash)
if (( BASH_VERSINFO[0] >= 4 )); then
  emit PASS H2 'host bash on PATH is 4+' "$host_bash"
else
  emit FAIL H2 'host bash on PATH is 4+' "$host_bash is $BASH_VERSION"
fi

# Clean up what the checks made. Paths a failed denial created are listed.
leftovers=()
for path in "$HOME/.claude/hooks/nono-probe-$tag" "$HOME/.claude/skills/nono-probe-$tag" \
  "$HOME/.claude/agents/nono-probe-$tag" "$HOME/.claude/commands/nono-probe-$tag" \
  "$HOME/.claude/output-styles/nono-probe-$tag" "$HOME/.pi/agent/extensions/nono-probe-$tag" \
  "/tmp/nono-escaped-$tag"; do
  [[ -e $path ]] && leftovers+=("$path")
done
for path in "$repo" "$HOME/.claude/.nono-probe-$tag" "$HOME/.cache/agents/nono-probe-$tag"; do
  [[ -e $path ]] && rip "$path"
done

pass=0 fail=0
for line in "${lines[@]}"; do
  IFS=$'\t' read -r result id label detail <<<"$line"
  case $result in
    PASS) colour=$green; ((pass++)) ;;
    FAIL) colour=$red; ((fail++)) ;;
    *) colour=$yellow ;;
  esac
  printf '%s%-4s%s %-3s %s%s\n' "$colour" "$result" "$off" "$id" "$label" "${detail:+ $dim($detail)$off}"
done
echo
echo "$pass passed, $fail failed. The manual probes are in $dotfiles/docs/unverified-probes.md."
if (( ${#leftovers[@]} )); then
  echo "Left behind by a failed denial (remove them with rip):"
  printf '  %s\n' "${leftovers[@]}"
fi
(( fail == 0 ))
