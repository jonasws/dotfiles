---
description: Hand a task to a pi in a herdr pane beside this one
argument-hint: "<task>"
---
Delegate this task to a pi child in a herdr pane, where the user can watch and
steer it: $@

1. Pick a short name `pi-<topic>` and start the child with
   `pi-herdr spawn pi-<topic>`. It opens in this directory, in a sandbox of its
   own. Add `-- --model <model>` only if the user named one.
2. Prompt it with everything it needs and nothing it can find itself: the goal,
   the files involved, the constraints, and how to know it is done. Tell it to
   write its result as Markdown to `.pi/results/<topic>.md` at the repository
   root (both of you can write there) and to reply only with that path.
   `pi-herdr prompt --wait --timeout 1800000 pi-<topic> "<prompt>"`
3. If the wait times out, read the pane before doing anything else
   (`herdr agent read pi-<topic> --source recent-unwrapped --lines 120`); a
   timeout does not mean the prompt was lost, so never resend it blindly.
4. Read the result file and report it. Leave the pane open unless the user says
   otherwise; `pi-herdr stop pi-<topic>` closes it.

Do not delegate several parts of one change in parallel: one child, one task.
