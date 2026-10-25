---
description: Review code with a fresh pi run through bash
argument-hint: "[what to review] [model]"
---
Spawn yourself as a sub-agent via bash to review: ${@:-the uncommitted changes in this repository}

Use `pi -p --no-session` with the review prompt as its argument. If the user
named a model, add `--model` with it. The sub-agent inherits this sandbox, so
it can read the repository but has no credentials and cannot ask for approval.

Ask the sub-agent to review for:
- bugs and logic errors
- security issues
- error handling gaps
- changes that do not match what the commit messages or the surrounding code
  say they do

and to cite file and line for every finding, strongest first.

Do not read the code yourself. Let the sub-agent do that. Report its findings
as it gave them, then say which ones you would act on.
