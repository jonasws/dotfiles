---
description: Gather the context for a task into a file, for a fresh session to start from
argument-hint: "<task>"
---
Gather the context needed for this task, but do not start on it: $@

Read whole files, not fragments: the entry points, every caller and callee of
the code the task touches, its tests, and the configuration and docs that
govern it. Follow references until nothing new turns up. Prefer the default
branch as pushed (`git grep` and `git show` on `origin/HEAD`) when the working
tree may be stale.

Write the result to `.pi/context/<short-slug>.md` at the repository root:

- the task, restated in one paragraph
- the relevant files, each with what it does and why it matters here
- the constraints and conventions an implementation must respect
- open questions you could not answer from the code
- a proposed approach, as numbered steps

Then stop, give the path, and suggest starting a fresh session with
`pi @.pi/context/<short-slug>.md`.
