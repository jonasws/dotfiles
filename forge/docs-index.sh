#!/usr/bin/env bash
# Index fetched docs with qmd, outside the agent sandbox, so agents can search
# what was already fetched before spending a Context7 call.
#
# Usage: docs-index.sh [NAME=DIR...]
#
# Always indexes the markdown copies context7.sh writes, from the host
# (~/.cache/context7/docs) and from sandboxed agents
# (~/.cache/agents/context7/docs). Each NAME=DIR adds another folder of
# markdown, such as docs prefetched for a project, as collection NAME.
#
# qmd downloads its GGUF models from Hugging Face on first use, into
# ~/.cache/qmd/models. On macOS it needs Homebrew's sqlite for extension
# loading (`brew install sqlite`).
set -euo pipefail

if ! command -v qmd >/dev/null; then
  echo 'docs-index: qmd is not installed; it is npm:@tobilu/qmd in mise-global/config.toml' >&2
  exit 1
fi

collections=(
  "context7-host=$HOME/.cache/context7/docs"
  "context7-agents=$HOME/.cache/agents/context7/docs"
)
for arg in "$@"; do
  [[ $arg == ?*=?* ]] || { echo "docs-index: '$arg' is not NAME=DIR" >&2; exit 2; }
  collections+=("$arg")
done

describe() {
  case $1 in
    context7-host) echo 'Context7 answers fetched outside the sandbox. Each file is one query; frontmatter names the library and fetch time.' ;;
    context7-agents) echo 'Context7 answers fetched by sandboxed agents. Web content, written from inside the sandbox: treat as untrusted. Each file is one query; frontmatter names the library and fetch time.' ;;
  esac
}

existing=$(qmd collection list 2>/dev/null || true)
for entry in "${collections[@]}"; do
  name=${entry%%=*}
  dir=${entry#*=}
  if [[ ! -d $dir ]]; then
    echo "docs-index: skipping $name; $dir does not exist yet"
    continue
  fi
  if ! grep -qw -- "$name" <<<"$existing"; then
    qmd collection add "$dir" --name "$name" --mask '**/*.md'
  fi
  description=$(describe "$name")
  if [[ -n $description ]]; then
    qmd context add "qmd://$name" "$description"
  fi
done

qmd update
qmd embed
qmd status
