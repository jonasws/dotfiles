---
name: markdown-preview
description: Render a markdown file with leaf in a Herdr split pane that reloads live whenever the file is saved, with pager keys and search. Use whenever the user asks to preview, render, view, read or watch a markdown file, or wants to see how a draft (README, docs, PR description, discussion comment, notes) will look, including right after you write or edit a .md file they will read. Invoked as /markdown-preview <file.md>. Needs HERDR_ENV=1; outside Herdr it only prints the leaf command to run.
argument-hint: "<file.md>"
---

# Markdown preview

Show a markdown file, rendered, in a pane beside the conversation, and keep it
current while the file changes.

Rendering markdown into the terminal output of a tool call loses the formatting
and costs context. A pane renders it properly, and because it reloads on save,
the user can read draft 1, ask for changes, and see draft 2 appear without
asking for another preview.

## When to use

- The user asks to preview, render, view, read or watch a `.md` file.
- You just wrote or rewrote a markdown file the user is meant to read or edit
  (a draft comment, a README, release notes) and a rendered view would help.
- `/markdown-preview <file.md>` is typed. The argument is the file.

Skip it when the user only wants the text in the conversation, or for a file
nobody will read.

## Procedure

1. **Check you are inside Herdr:**

   ```bash
   test "${HERDR_ENV:-}" = 1
   ```

   If not, the script says so and prints `leaf -w <file>`. Pass that command
   on to the user and stop.

2. **Open the preview:**

   ```bash
   bash ~/.claude/skills/markdown-preview/preview.sh <file>
   ```

   - It splits the pane you run in, to the right, without taking focus, so the
     user keeps typing where they were.
   - `--direction down` stacks it instead, which suits a narrow window.
   - `--focus` moves focus into the preview, only if the user asked for it.

3. **Report the pane id** the script prints, and that the preview reloads when
   the file is saved. It is a pager: `j`/`k`, `d`/`u`, `g`/`G` scroll, `/`
   searches, `t` toggles the table of contents, `?` lists the keys, and `q`
   closes the pane.

## Refreshing and closing

- Editing the file is enough. Do not reopen it. Running the script again for a
  file whose pane is still open reports that and does nothing.
- To close it:

  ```bash
  bash ~/.claude/skills/markdown-preview/preview.sh --close <file>
  ```

## Why it works this way

- **leaf, not mdcat.** `mdcat --watch` re-renders but has no pager, and mdcat
  refuses `--watch` with `--paginate`, so a live mdcat view cannot scroll.
  `glow -t` has both but renders a blank pane inside Herdr. leaf (`-w`) reloads
  in place, keeps the scroll position across a save, and renders in Herdr.
- **Pane per file, found by label.** The pane is renamed `leaf <basename>` and
  started in the file's directory; that pair identifies it on the next call.
  No state file, so it also works from a sandbox that cannot write to
  `~/.local/state`.
- **`exec leaf`.** leaf replaces the pane's shell, so `q` ends the process and
  Herdr closes the pane instead of leaving a prompt behind.
- **Splits `--current`.** It targets the pane the command runs in. With two
  Herdr clients attached, "the focused pane" can belong to the other one.
- **Starts the command through the environment** when the fish helper
  (`50-herdr-exec.fish`) exists, because keystrokes sent to a pane before its
  shell has started are dropped. Without the helper it types the command after
  a short wait.

## Rules

- Never `Read` the pane back to check the render. The user sees it; a bounded
  `herdr pane read <pane> --lines 3` is fine if you must confirm it started.
- Do not close a preview you did not open, and do not close one the user is
  still reading unless asked. Say it can be closed with `--close`.
- Do not preview files with secrets in them. The pane scrollback persists.
