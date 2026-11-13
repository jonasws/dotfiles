#!/usr/bin/env nu
# State of an ECS service's most recent service deployment, as one JSON record
# for watch-ecs-deployment.py to patch into its TML surface.

use watch-lib.nu [aws-json clock last-segment mins-secs]

const LABELS = {
  PENDING: "Deployment pending"
  IN_PROGRESS: "Rolling out"
  SUCCESSFUL: "Deployment succeeded"
  STOPPED: "Deployment stopped"
  STOP_REQUESTED: "Stop requested"
  ROLLBACK_REQUESTED: "Rollback requested"
  ROLLBACK_IN_PROGRESS: "Rolling back"
  ROLLBACK_SUCCESSFUL: "Rolled back"
  ROLLBACK_FAILED: "Rollback failed"
}

# Extra credit, left out for now:
# - describe-service-revisions answers the same for a given revision ARN, so it
#   need only run when the deployment's target revision changes. This script is a
#   fresh process on every poll, so the cache would have to be kept by the caller
#   (pass the last revision's taskDef and images in, and return the ARN used) or
#   in a file keyed by ARN.
# - describe-services (the events) does not depend on the deployment lookup. It
#   could run beside list-service-deployments with `par-each`, and the revision
#   call beside it once the deployment ARN is known, to shave a round trip off
#   every poll.
def main [service: string, cluster: string] {
  let listed = aws-json [ecs list-service-deployments "--cluster" $cluster "--service" $service "--max-results" "10"]
    | get serviceDeployments

  if ($listed | is-empty) {
    return ({
      status: "NONE"
      statusLabel: "No service deployments in the last 90 days"
      statusState: "idle"
      updated: (clock (date now))
    } | to json --raw)
  }

  let latest = $listed | sort-by {|d| $d.createdAt | into datetime } | last | get serviceDeploymentArn
  let d = aws-json [ecs describe-service-deployments "--service-deployment-arns" $latest]
    | get serviceDeployments | first
  let target = $d.targetServiceRevision? | default {}
  let rev = aws-json [ecs describe-service-revisions "--service-revision-arns" $target.arn]
    | get serviceRevisions | first
  let events = aws-json [ecs describe-services "--cluster" $cluster "--services" $service]
    | get services | first | get events

  let status = $d.status
  let start = $d.startedAt? | default $d.createdAt | into datetime
  let end = $d.finishedAt? | default ($d.stoppedAt?)
  let end = if $end == null { null } else { $end | into datetime }
  let seconds = ((($end | default (date now)) - $start) / 1sec | into int)
  let sources = $d.sourceServiceRevisions? | default []
  let breaker = $d.deploymentCircuitBreaker? | default {}
  let rollback = $d.rollback?
  let since = $start - 5sec

  let prefix = "(service " + $service
  let events = $events
    | where {|e| ($e.createdAt | into datetime) >= $since }
    | first 40
    | each {|e| {
        id: $e.id
        time: (clock $e.createdAt)
        message: ($e.message | str replace $"($prefix)) " "" | str replace $"($prefix), " "(")
      } }

  {
    service: $service
    cluster: ($cluster | last-segment "/")
    status: $status
    statusLabel: ($LABELS | get --optional $status | default $status)
    statusState: (
      if $status == "SUCCESSFUL" { "done" } else if ($status =~ "ROLLBACK|STOP") { "errored" } else { "working" }
    )
    reason: ($d.statusReason? | default "")
    started: (clock $start)
    finished: (clock $end)
    elapsed: (mins-secs $seconds)
    updated: (clock (date now))
    requested: ($target.requestedTaskCount? | default 0)
    running: ($target.runningTaskCount? | default 0)
    pending: ($target.pendingTaskCount? | default 0)
    oldRequested: ($sources | each {|s| $s.requestedTaskCount? | default 0 } | math sum)
    oldRunning: ($sources | each {|s| $s.runningTaskCount? | default 0 } | math sum)
    breaker: ($breaker.status? | default "-")
    breakerFailures: ($breaker.failureCount? | default 0)
    breakerThreshold: ($breaker.threshold? | default 0)
    rollback: (
      if $rollback == null { "" } else { $"($rollback.reason? | default '') \(from (clock $rollback.startedAt?)\)" }
    )
    alarms: ($d.alarms?.status? | default "-")
    taskDef: ($rev.taskDefinition | last-segment "/")
    images: ($rev.containerImages? | default [] | each {|c| $c.image | last-segment "/" } | str join ", ")
    deploymentId: ($d.serviceDeploymentArn | last-segment "/")
    events: $events
  } | to json --raw
}
