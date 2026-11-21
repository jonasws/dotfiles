---
name: draft-pane
description: Open a text file in a tuios pane beside the conversation, rendered by leaf and reloaded on every save, where the user can also press Ctrl+E to edit it in Neovim. Use whenever you write text the user should review or edit before it is sent, posted or committed (a PR description, Jira or GitHub comment, a commit message the user wants to see first, Slack message, release notes, a README section), when the user asks to preview, render, view, watch, open or edit a draft or markdown file, or asks to "open it in nvim" or "let me edit it". Invoked as /draft-pane <file>. Needs TUIOS_ENV=1; outside tuios it only prints the leaf command to run. Not for shareable documents (the docs skill) or for reviewing diffs (hunk-review, tuicr).
argument-hint: "<file>"
---

# Draft pane

Show a draft in a pane beside the conversation, rendered, and let the user edit
it in place. One pane covers both reading and editing, so there is no choice to
make between a preview and an editor.

- `leaf -w` renders the file and reloads it whenever it is saved, by you or by
  the user.
- `Ctrl+E` in leaf opens the file in Neovim (leaf's `editor` setting, at the
  line on screen) inside the same pane. Quitting Neovim returns to leaf, which
  reloads.

Printing a draft into the conversation loses the formatting and costs context;
the pane shows it properly and stays current across revisions.

## When to use

- You wrote or rewrote text the user should review before it is sent, posted
  or committed: open it without being asked.
- The user asks to preview, view, open or edit a draft or a markdown file.
- `/draft-pane <file>` is typed.

Skip it when the user wants the text in the conversation, for files nobody
will read, and for commits you make yourself unless the user asked to see the
message first. Files in the repo that the user edits as part of the work are theirs
to open.

## Procedure

1. **Write the draft to a file.** Use the scratchpad for drafts that are sent
   somewhere else, with an absolute path and a `.md` extension. leaf renders a
   commit message or plain text fine as markdown.

2. **Check you are in tuios:** `test "${TUIOS_ENV:-}" = 1`. If not, give the
   user `leaf -w <file>` to run and stop.

3. **Reuse an open pane.** One pane per file, named `draft <basename>`:

   ```bash
   tuios list-windows --json | jq -r --arg n "draft $(basename "$file")" \
     '.windows[] | select(.display_name == $n) | .window_id'
   ```

   If it prints an id, the pane is already showing the file and reloads on
   save. Say so and stop.

4. **Open it,** with the literal name, directory and path written in:

   ```bash
   tuios split-window right --no-focus --name 'draft notes.md' \
     --cwd '/abs/dir' -- leaf -w '/abs/dir/notes.md'
   ```

   The `pane-control-guard` hook lets a pane that only runs `leaf -w` open
   without a prompt. A `$(...)` anywhere in the command makes it ask.

   - `--no-focus` leaves the user where they are. Drop it when they asked to
     edit now.
   - `down` instead of `right` suits a narrow window.
   - **Do not pass `--grants`.** The pane is the user's, not a helper's.
     Neovim's Ctrl+hjkl crosses into other panes through tuios, and moving
     focus needs the `admin` grant, so a pane with `none`, `read` or
     `read,write` silently loses pane navigation.
   - leaf is the pane's only program, so quitting it (`q`) closes the pane.

   **When `split-window` answers `forbidden`**, your pane lacks tuios's `admin`
   grant, which starting a pane needs. Show the draft as a TML surface instead,
   which needs only `write` and starts no process:

   ```bash
   esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$1"; }
   { printf '<tml version="1" title="draft %s"><markdown>' "$(basename "$file")"
     esc "$file"; printf '</markdown></tml>\n'; } >"$file.tml"
   tuios tml show "$file.tml" --pane
   ```

   After each revision, rebuild the `.tml` and run `tuios tml replace <surface>
   "$file.tml"` with the surface id `tml show` printed. The user edits by
   opening the file themselves (`leaf -w <file>` in a pane of their own); say
   that, with the path.

5. **Tell the user** the pane is open, that it reloads on save, and that
   `Ctrl+E` edits it in Neovim and `q` closes it.

## Editing hand-off

The file has two writers, you and the user. Keep them apart:

- Once the user says they will edit, do not write the file until they say they
  are done. Neovim would warn about a changed file, and one side's edits
  would be lost.
- When they are done, read the file again and treat that as the current text.
  Do not rely on what you wrote earlier.
- Revisions you make are saved to the same file; leaf shows them. Do not open a
  second pane.

## Closing

- `tuios close-window "draft <basename>"`, for a pane you opened, once the
  draft has been used or the user asks. Leave a pane the user is still reading.
- Remove a scratchpad draft with `rip` once it has been used, unless the user
  wants to keep it.

## Rules

- Never capture the pane to check the render. The user sees it.
- Do not open files with secrets in a pane; the scrollback persists.

## Known limit

Neovim started from leaf does not show as the pane's foreground program in
tuios (only `leaf` does), so herdr-splits treats the pane as a plain one:
Ctrl+hjkl always moves between tuios panes, never between Neovim splits, and
Ctrl+H in insert mode moves panes instead of deleting a character. For a
single-window draft this rarely matters.
