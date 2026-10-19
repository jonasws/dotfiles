#!/usr/bin/env bash
# Render a sibling service's OpenAPI spec into LLM-ready markdown with ppress.
#
# Usage: render-api-docs.sh <repo-dir | spec-file> [--working-tree]
#
#   repo-dir        a clone under ~/CX, ~/CNOPS or ~/CN-TERMINAL; its spec is
#                   located with fd and rendered as it stands on origin/HEAD
#   spec-file       a spec inside a clone, to pick one when a repo has several,
#                   or an external spec dropped loose in a workspace root
#   --working-tree  render the checked-out spec instead of origin/HEAD, for
#                   questions about the branch that is checked out
#
# Output lands in <workspace-root>/api-docs/<name>/, outside every git repo.
# Rendering takes well under a second, so callers re-render rather than
# reasoning about staleness.
set -euo pipefail

target=${1:?usage: render-api-docs.sh <repo-dir | spec-file> [--working-tree]}
working_tree=false
[[ ${2:-} == --working-tree ]] && working_tree=true

target=$(cd "$(dirname "$target")" && pwd)/$(basename "$target")

workspace_root() {
  local r
  for r in "$HOME/CX" "$HOME/CNOPS" "$HOME/CN-TERMINAL"; do
    [[ $1 == "$r"/* ]] && { echo "$r"; return; }
  done
  dirname "$1"
}

# When the spec itself last changed, which says more about freshness than the
# ref: a service can see daily commits while its contract stands still.
spec_changed() {
  local repo_dir=$1 rev=$2 rel=$3 file=$4 commit
  if [[ $rev == HEAD && -n $(git -C "$repo_dir" status --porcelain -- "$rel") ]]; then
    echo "uncommitted edits, file modified $(date -r "$file" '+%Y-%m-%d %H:%M')"
    return
  fi
  commit=$(git -C "$repo_dir" log -1 --format='%h %cs (%cr)' "$rev" -- "$rel")
  echo "${commit:-never committed on $rev}"
}

root=$(workspace_root "$target")
specs_dir="$root/api-docs/.specs"
mkdir -p "$specs_dir"

repo=${target#"$root"/}
repo=${repo%%/*}
repo_dir="$root/$repo"

if [[ ! -d $repo_dir/.git ]]; then
  [[ -f $target ]] || { echo "$target is neither a spec file nor inside a git clone" >&2; exit 1; }
  name=$(basename "${target%.*}")
  spec=$target
  ref="file"
  changed="file modified $(date -r "$spec" '+%Y-%m-%d %H:%M')"
else
  name=$repo
  if [[ -f $target ]]; then
    found=("$target")
  else
    # Snapshot specs are what the service's contract test pins, so they sort
    # first. openapitools.json is generator config, never a spec.
    mapfile -t found < <(
      fd -t f -p -E node_modules -E target -E build -E cdk.out \
        '(__snapshots__/openapi-schema\.json|openapi\.(json|ya?ml)|swagger\.(json|ya?ml))$' "$repo_dir" |
        awk '{ print (/__snapshots__/ ? 0 : 1) "\t" $0 }' | sort | cut -f2-
    )
  fi
  if ((${#found[@]} == 0)); then
    echo "no OpenAPI spec found in $repo_dir" >&2
    exit 1
  fi
  if ((${#found[@]} > 1)); then
    printf 'several specs found, rendering the first; pass a spec path to pick another:\n' >&2
    printf '  %s\n' "${found[@]}" >&2
  fi
  rel=${found[0]#"$repo_dir"/}

  if $working_tree; then
    spec=${found[0]}
    ref="working tree ($(git -C "$repo_dir" branch --show-current || true))"
    ref=${ref/\(\)/(detached HEAD)}
    changed=$(spec_changed "$repo_dir" HEAD "$rel" "$spec")
  else
    # The Claude Code sandbox points TMPDIR at /tmp/claude-<uid> and blocks
    # writes to a sibling clone's .git, so a fetch there can only fail.
    if [[ ${TMPDIR:-} == @(/private|)/tmp/claude-* ]]; then
      echo "sandboxed: skipping fetch; using origin/HEAD as last fetched" >&2
    else
      GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" git -C "$repo_dir" fetch --quiet origin 2>/dev/null || echo "fetch failed; using origin/HEAD as last fetched" >&2
    fi
    spec="$specs_dir/$name.${rel##*.}"
    if git -C "$repo_dir" show "origin/HEAD:$rel" >"$spec" 2>/dev/null; then
      ref="origin/HEAD $(git -C "$repo_dir" log -1 --format='%h %cr' origin/HEAD)"
      changed=$(spec_changed "$repo_dir" origin/HEAD "$rel" "$spec")
    else
      spec=${found[0]}
      ref="working tree ($rel is not on origin/HEAD)"
      changed=$(spec_changed "$repo_dir" HEAD "$rel" "$spec")
    fi
  fi
fi

out="$root/api-docs/$name"
if [[ -d $out ]]; then
  [[ -f $out/AGENTS.md ]] || { echo "refusing to replace $out: not a ppress output" >&2; exit 1; }
  rm -rf "$out"
fi

log=$(mktemp)
if ! ppress -b --no-html --no-json -o "$out" "$spec" >"$log" 2>&1; then
  cat "$log" >&2
  rm -f "$log"
  exit 1
fi
rm -f "$log"

echo "$out"
echo "spec:    ${rel:-$spec}"
echo "raw:     $spec"
echo "ref:     $ref"
echo "changed: $changed"
