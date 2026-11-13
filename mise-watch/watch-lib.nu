# Helpers shared by the watch-*-state.nu scripts.

# Run `aws` and parse its JSON. On failure, print only aws's last stderr line and
# exit 1, which is what the Python watcher shows as "poll failed: ...".
export def aws-json [args: list<string>] {
  let region = $env.AWS_REGION? | default ($env.AWS_DEFAULT_REGION? | default "eu-west-1")
  let r = do { ^aws --region $region --output json ...$args } | complete
  if $r.exit_code != 0 {
    print --stderr ($r.stderr | str trim | lines | last | default "aws failed")
    exit 1
  }
  if ($r.stdout | str trim | is-empty) { {} } else { $r.stdout | from json }
}

# HH:MM:SS in the local zone, or "-" for null.
export def clock [t?: any] {
  if $t == null { "-" } else { $t | into datetime | date to-timezone local | format date "%H:%M:%S" }
}

# "12m 3s" for a number of seconds.
export def mins-secs [seconds: int] {
  $"($seconds // 60)m ($seconds mod 60)s"
}

# The part after the last SEP, e.g. the name at the end of an ARN.
export def last-segment [sep: string] {
  split row $sep | last
}
