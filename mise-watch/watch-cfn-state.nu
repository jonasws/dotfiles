#!/usr/bin/env nu
# State of a CloudFormation stack's latest operation, as one JSON record for
# watch-cfn-deployment.py to patch into its TML surface.

use watch-lib.nu [aws-json clock mins-secs]

# Stack-level statuses that begin an operation; the latest one marks its start.
const START = [CREATE_IN_PROGRESS UPDATE_IN_PROGRESS DELETE_IN_PROGRESS IMPORT_IN_PROGRESS]

# Failures CloudFormation reports as a consequence of another resource failing.
const KNOCK_ON = '(?i)cancelled|resource\(s\) failed to'

def state-of [status: string] {
  if ($status | str ends-with "_IN_PROGRESS") {
    "working"
  } else if ($status | str contains "ROLLBACK") or ($status | str ends-with "_FAILED") {
    "errored"
  } else {
    "done"
  }
}

def role-of [status: string] {
  if ($status | str ends-with "_FAILED") or (($status | str contains "ROLLBACK") and ($status | str ends-with "_COMPLETE")) {
    "error"
  } else if ($status | str ends-with "_IN_PROGRESS") {
    "warning"
  } else if ($status | str ends-with "_COMPLETE") {
    "success"
  } else {
    "mute"
  }
}

# Failed first, then in progress, then the rest.
def rank [status: string] {
  if ($status | str ends-with "_FAILED") { 0 } else if ($status | str ends-with "_IN_PROGRESS") { 1 } else { 2 }
}

def clip [reason?: any] {
  $reason | default "" | str substring --grapheme-clusters 0..299
}

# Events of the latest operation, newest first, read page by page until its start.
def operation-events [stack: string] {
  mut events = []
  mut token: any = null
  loop {
    let extra = if $token == null { [] } else { ["--starting-token" $token] }
    let page = aws-json ([cloudformation describe-stack-events "--stack-name" $stack "--max-items" "100"] ++ $extra)
    for e in ($page.StackEvents? | default []) {
      $events = $events | append $e
      if $e.ResourceType == "AWS::CloudFormation::Stack" and $e.LogicalResourceId == $stack and $e.ResourceStatus in $START {
        return $events
      }
    }
    $token = $page.NextToken?
    if $token == null { return $events }
  }
}

def main [stack: string, account: string] {
  let summary = aws-json [cloudformation describe-stacks "--stack-name" $stack] | get Stacks | first
  let status = $summary.StackStatus
  let events = operation-events $stack
  let running = $status | str ends-with "_IN_PROGRESS"

  let start = if ($events | is-empty) { null } else { $events | last | get Timestamp | into datetime }
  let end = if ($events | is-empty) or $running { null } else { $events | first | get Timestamp | into datetime }
  let elapsed = if $start == null { "-" } else { mins-secs ((($end | default (date now)) - $start) / 1sec | into int) }

  # Newest event per resource; the stack's own events are not resources.
  let resources = $events
    | where LogicalResourceId != $stack
    | uniq-by LogicalResourceId
    | sort-by {|e| $e.Timestamp | into datetime } --reverse
    | sort-by {|e| rank $e.ResourceStatus }
    | each {|e| {
        id: $e.LogicalResourceId
        type: ($e.ResourceType | str replace "AWS::" "")
        status: $e.ResourceStatus
        role: (role-of $e.ResourceStatus)
        time: (clock $e.Timestamp)
        reason: (clip $e.ResourceStatusReason?)
      } }
  let statuses = $resources | get status

  let failures = $events | reverse | where {|e| $e.ResourceStatus | str ends-with "_FAILED" }
  let root = $failures | where {|e| not (($e.ResourceStatusReason? | default "") =~ $KNOCK_ON) } | append $failures | get 0?

  {
    stack: $stack
    account: $account
    status: $status
    statusLabel: ($status | str replace --all "_" " " | str lowercase | str capitalize)
    statusState: (state-of $status)
    statusRole: (role-of $status)
    operation: (
      if ($events | is-empty) { "-" } else { $events | last | get ResourceStatus | str replace --regex '_IN_PROGRESS$' '' | str lowercase }
    )
    reason: ($summary.StackStatusReason? | default "")
    rootCause: (if $root == null { "" } else { $"($root.LogicalResourceId): ($root.ResourceStatusReason? | default '')" })
    started: (clock $start)
    finished: (clock $end)
    elapsed: $elapsed
    updated: (clock (date now))
    inProgress: ($statuses | where {|s| $s | str ends-with "_IN_PROGRESS" } | length)
    complete: ($statuses | where {|s| $s | str ends-with "_COMPLETE" } | length)
    failed: ($statuses | where {|s| $s | str ends-with "_FAILED" } | length)
    touched: ($resources | length)
    resources: $resources
    events: (
      $events | first 100 | each {|e| {
        key: $e.EventId
        time: (clock $e.Timestamp)
        status: $e.ResourceStatus
        role: (role-of $e.ResourceStatus)
        id: $e.LogicalResourceId
        reason: (clip $e.ResourceStatusReason?)
      } }
    )
  } | to json --raw
}
