---
name: markdown-preview
description: Render a markdown file with mdcat in a Herdr split pane that redraws live whenever the file is saved. Use whenever the user asks to preview, render, view, read or watch a markdown file, or wants to see how a draft (README, docs, PR description, discussion comment, notes) will look, including right after you write or edit a .md file they will read. Invoked as /markdown-preview <file.md>. Needs HERDR_ENV=1; outside Herdr it only prints the mdcat command to run.
argument-hint: "<file.md>"
---

# Markdown preview

Show a markdown file, rendered, in a pane beside the conversation, and keep it
current while the file changes.

Rendering markdown into the terminal output of a tool call loses the formatting
and costs context. A pane renders it properly, and because it redraws on save,
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

   If not, the script says so and prints `mdcat -p <file>`. Pass that command
   on to the user and stop.

2. **Open the preview:**

   ```bash
   bash ~/.claude/skills/markdown-preview/preview.sh <file>
   ```

   - It splits the pane you run in, to the right, without taking focus, so the
     user keeps typing where they were.
   - `--direction down` stacks it instead, which suits a narrow window.
   - `--focus` moves focus into the preview, only if the user asked for it.

3. **Report the pane id** the script prints, and that the preview redraws when
   the file is saved. Ctrl-C in the pane closes it; it is a live view, not a
   pager, so `q` does nothing.

## Refreshing and closing

- Editing the file is enough. Do not reopen it. Running the script again for a
  file whose pane is still open reports that and does nothing.
- To close it:

  ```bash
  bash ~/.claude/skills/markdown-preview/preview.sh --close <file>
  ```

- For a one-shot paged view with no live refresh, tell the user to run
  `mdcat -p <file>` themselves.

## Why it works this way

- **Pane per file.** The pane id is stored under
  `~/.local/state/markdown-preview/`, keyed by the file's absolute path, so a
  second call finds the pane it opened earlier instead of piling up splits.
- **`mdcat --watch` does the refreshing.** It re-renders on every change and
  keeps working across repeated saves that replace the file, which is how many
  editors and tools write. No separate watcher is needed.
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
