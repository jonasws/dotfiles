# Working rules

User-level instructions for every omp session. A repository's own AGENTS.md
or CLAUDE.md loads after this one and governs that repository.

## Environment

- macOS on Apple silicon. Interactive shell is fish; your bash tool is omp's
  embedded bash. Tools come from mise (`mise which <tool>`, `mise x -- ...`).
- You run inside a nono sandbox. Writable: `~/CX`, `~/CNOPS`, `~/CN-TERMINAL`,
  `~/dotfiles` (except `bin/`, `claude/`, `fish/`, `fnox/`, `git/`, `herdr/`,
  `mise-global/`, `nono/` and `omp/`),
  `~/.herdr/worktrees`, `~/.m2/repository`, `~/.omp` and the working directory.
  Most of `~` is unreadable, as are `.env` files, `~/.ssh` and `~/.aws`.
  Writing `.git/hooks`, `.git/config`, `.claude/settings*.json`, `.mcp.json`,
  `.envrc`, `.vscode/` or `.idea/` is denied. An "Operation not permitted" on
  any of these is the sandbox; say so and stop rather than work around it.
- `$TMPDIR` is `/tmp/omp-<uid>/`. Put scratch files there, not in the repo.
- 1Password is unreachable, so `fnox`, `op` and `gh` resolve nothing. `mvn`
  runs `--offline` against `~/.m2/repository`; if a dependency is missing,
  tell me to run the build outside.

## Search and code tools

Match the tool to the question:

| Question | Tool |
|---|---|
| Who calls X, what implements it, rename | `lsp` (references, implementations, call hierarchy) |
| Match depends on syntax shape, or a codemod | `ast_grep` / `ast_edit` |
| Literal text or regex, file lookup | `grep`, `glob` |

- LSP answers from the compiler's resolution; prefer it wherever a server runs
  (Kotlin, TypeScript, Rust). It needs a file and a position.
- Use the native `read`/`grep`/`glob`/`edit` tools rather than `cat`, `rg`,
  `find` or `sed -i` in bash. For find-and-replace across files in bash, `sd`.
- Delegate with `task` when work splits into independent parts; use
  `isolated: true` when workers edit the same files.

## GitHub

- Never `gh`: it is denied and holds no credentials. The `github` MCP server is
  read-only and sees public repositories only.
- `nsbno` and `capralifecycle` repos are private. Search the clones under
  `~/CX`, `~/CNOPS` and `~/CN-TERMINAL`, not the MCP server, where they come
  back empty. If a repo is not cloned, say so.
- For "what does the default branch do", read the pushed ref, not the checkout:

  ```bash
  git -C ~/CX/<repo> fetch --quiet origin
  git -C ~/CX/<repo> grep -n '<pattern>' origin/HEAD -- '*.kt'
  git -C ~/CX/<repo> show origin/HEAD:path/to/File.kt
  git -C ~/CX/<repo> log -1 --format='%h %cr' origin/HEAD   # cite this
  ```

- `github.com/jonasws/dotfiles` (`~/dotfiles`) is public: nothing from the org
  repos and no secrets go there.
- Writes and private-repo lookups are mine: tell me the `gh` command.

## herdr

herdr panes run outside the sandbox with my full rights. Read freely (`herdr
pane list/read`, `agent list/read/wait`); create tabs and splits with
`--no-focus`. Only run commands in panes you created, never send input to my
shells or to other agents, and start further agents only as `herdr agent start
<name> --kind omp`. Close only panes you opened. Never talk to herdr.sock or
docker.sock directly.

## Commits

- Conventional subject (`feat(scope): ...`); indent the body with 2 spaces.
- No session links, session IDs or `Co-Authored-By` trailers.
- Commits come out unsigned (signing needs 1Password). Do not pass `-S`. After
  committing, tell me how many unsigned commits there are and remind me to run
  `resign-commits`.
- Never push unless I ask. Force-push, `reset --hard`, `clean -f` and rebase
  ask for approval.

## Responses

Concise wording, complete findings: keep every relevant source and caveat, and
mark what is measured versus assumed. End with a next step only when a
decision of mine is pending.

## Code comments

Comment the non-obvious why. No comments that restate the code, and none that
narrate mistakes made along the way.
