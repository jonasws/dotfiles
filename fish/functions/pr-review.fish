function pr-review --description "Print a PR's GitHub reviews as markdown, without a TUI"
    argparse a/all h/help -- $argv
    or return 2

    if set -q _flag_help; or test (count $argv) -gt 1
        echo "usage: pr-review [--all] [pr-number]   # defaults to the current branch's PR; --all keeps resolved and outdated threads" >&2
        return 2
    end

    # Same reviewThreads query tuicr runs for `tuicr pr`. Without a number the PR
    # is found by head branch in the same request; gh fills in {owner}, {repo}
    # and {branch} from the current checkout.
    set -l query '
fragment Review on PullRequest {
  number title url
  reviews(first: 100) { nodes { author { login } state body } }
  reviewThreads(first: 100) {
    nodes {
      isResolved isOutdated path line startLine originalLine
      comments(first: 100) { nodes { author { login } body } }
    }
  }
  comments(first: 100) { nodes { author { login } body } }
}
query($owner: String!, $repo: String!, $pr: Int!, $branch: String!, $byNumber: Boolean!) {
  repository(owner: $owner, name: $repo) {
    byNumber: pullRequest(number: $pr) @include(if: $byNumber) { ...Review }
    byBranch: pullRequests(headRefName: $branch, states: OPEN, first: 1) @skip(if: $byNumber) {
      nodes { ...Review }
    }
  }
}'

    set -l pr 0
    set -l by_number false
    if set -q argv[1]
        set pr $argv[1]
        set by_number true
    end

    set -l include_all false
    set -q _flag_all; and set include_all true

    gh api graphql -f query=$query -F owner='{owner}' -F repo='{repo}' \
        -F pr=$pr -F branch='{branch}' -F byNumber=$by_number \
        | jq -r --argjson all $include_all '
def indent: gsub("\r"; "") | gsub("\n"; "\n   ");
def who: .author.login // "ghost";
(.data.repository | .byNumber // .byBranch.nodes[0]) as $pr
| if $pr == null then "pr-review: no open PR for the current branch\n" | halt_error(1) else . end
| ($pr.reviewThreads.nodes | map(select($all or ((.isResolved or .isOutdated) | not)))) as $threads
| ($pr.reviews.nodes | map(select(.body != ""))) as $reviews
| ($pr.comments.nodes) as $conversation
| "# PR #\($pr.number): \($pr.title)\n\($pr.url)\n",
  (if ($reviews | length) > 0 then "## Review summaries\n",
    ($reviews[] | "- **\(who)** (\(.state)): \(.body | indent)"), "" else empty end),
  (if ($threads | length) > 0 then "## Inline threads\n",
    ($threads | to_entries[] | .key as $i | .value as $t
      | ($t.line // $t.originalLine) as $end
      | (if $t.startLine and $t.startLine != $end then "\($t.startLine)-\($end)" else "\($end)" end) as $lines
      | ([if $t.isResolved then "resolved" else empty end, if $t.isOutdated then "outdated" else empty end]
          | if length > 0 then " [\(join(", "))]" else "" end) as $state
      | "\($i + 1). `\($t.path):\($lines)`\($state)",
        ($t.comments.nodes[] | "   - **\(who)**: \(.body | indent)")), "" else empty end),
  (if ($conversation | length) > 0 then "## Conversation\n",
    ($conversation[] | "- **\(who)**: \(.body | indent)") else empty end)'
end
