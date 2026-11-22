#!/usr/bin/env bash
# Battle test of AWS inside the nono agent sandbox. Run it inside nono:
#
#   mise -C ~/dotfiles run nono:battle-aws -- [PROFILE] [BUCKET] [--interactive]
#   (or, in an agent pane: ! bash ~/dotfiles/nono/battle/aws.sh ...)
#
# PROFILE defaults to the first -readonly profile; BUCKET (optional) is one the
# profile may list. Each check names the layer expected to decide it:
#
#   ok      the call succeeds
#   nono    nono's proxy refuses it: a bare 403 with no AWS error code
#           (endpoint_policy: only Describe/List/Get/BatchGet/Search/Lookup,
#           GET/HEAD for REST services, GetCallerIdentity for STS)
#   iam     nono passes it, AWS refuses it: the readonly session policy
#
# Write probes target resources that do not exist, or use --dry-run, so a probe
# that slips past both layers fails at AWS without changing anything; it is
# reported as "reached AWS". Nothing here creates, changes or deletes.
#
# Then on the host: nono audit list --recent 1; nono audit show <id>
# shows the route, operation and rule behind each decision.

set -u
profile=${1:-}
bucket=${2:-}
interactive=false
for a in "$@"; do [ "$a" = --interactive ] && interactive=true; done
[ "$bucket" = --interactive ] && bucket=
[ "$profile" = --interactive ] && profile=

pass=0 fail=0
green=$'\e[32m' red=$'\e[31m' dim=$'\e[2m' off=$'\e[0m'

verdict() {
  # $1 rc, $2 output -> ok | unsigned | iam | slipped | nono | other
  local rc=$1 out=$2
  if [ "$rc" -eq 0 ]; then echo ok; return; fi
  case $out in
  *InvalidClientTokenId* | *InvalidAccessKeyId* | *UnrecognizedClient* | *SignatureDoesNotMatch* | *IncompleteSignature*) echo unsigned ;;
  *DryRunOperation*) echo slipped ;;
  *AccessDenied* | *UnauthorizedOperation* | *AuthorizationError* | *"not authorized"*) echo iam ;;
  *NotFound* | *NoSuch* | *"does not exist"* | *NonExistent* | *ValidationError* | *InvalidParameter*) echo slipped ;;
  *"(403)"* | *Forbidden*) echo nono ;;
  *) echo other ;;
  esac
}

check() {
  # check EXPECT LABEL -- command...
  local expect=$1 label=$2
  shift 3
  local out rc got
  out=$("$@" 2>&1)
  rc=$?
  got=$(verdict "$rc" "$out")
  if [ "$got" = "$expect" ]; then
    pass=$((pass + 1))
    printf '%sPASS%s %-7s %s\n' "$green" "$off" "$expect" "$label"
  else
    fail=$((fail + 1))
    [ "$got" = slipped ] && got="reached AWS"
    printf '%sFAIL%s %-7s %s %s(got: %s)%s\n' "$red" "$off" "$expect" "$label" "$dim" "$got" "$off"
    printf '%s     %s%s\n' "$dim" "$(printf '%s' "$out" | tail -n 2 | tr '\n' ' ' | cut -c1-200)" "$off"
  fi
}

fact() {
  # fact LABEL CONDITION-COMMAND...
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    pass=$((pass + 1))
    printf '%sPASS%s %-7s %s\n' "$green" "$off" fact "$label"
  else
    fail=$((fail + 1))
    printf '%sFAIL%s %-7s %s\n' "$red" "$off" fact "$label"
  fi
}

no_aws_secrets_in_env() { ! env | grep -qE '^AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY|SESSION_TOKEN)='; }
placeholders_only() {
  [ -r "${AWS_CONFIG_FILE:-}" ] && grep -q '^aws_access_key_id' "$AWS_CONFIG_FILE" &&
    ! grep -E '^aws_access_key_id' "$AWS_CONFIG_FILE" | grep -vq NONOPLACEHOLDER
}
unreadable() { ! cat "$1"; }
exported_key_is_placeholder() {
  aws configure export-credentials --profile "$profile" --format env 2>/dev/null |
    grep -q '^export AWS_ACCESS_KEY_ID=NONOPLACEHOLDER'
}

echo "== Containment"
fact "AWS_CONFIG_FILE is the placeholder config" test -r "${AWS_CONFIG_FILE:-/nonexistent}"
fact "no AWS key, secret or session token in the environment" no_aws_secrets_in_env
fact "every access key in the config is a placeholder" placeholders_only
fact "~/.aws/config is unreadable" unreadable "$HOME/.aws/config"
fact "~/.aws/credentials is unreadable" unreadable "$HOME/.aws/credentials"

profiles=$(aws configure list-profiles 2>/dev/null)
[ -n "$profile" ] || profile=$(printf '%s\n' "$profiles" | head -n 1)
[ -n "$profile" ] || { echo "no profiles in $AWS_CONFIG_FILE" >&2; exit 2; }
fact "the SDK resolves $profile to placeholder keys" exported_key_is_placeholder
p=(--profile "$profile" --no-cli-pager)

echo "== Identity, every profile (nono re-signs as the host profile)"
for each in $profiles; do
  check ok "sts get-caller-identity --profile $each" -- aws sts get-caller-identity --profile "$each" --no-cli-pager
done

echo "== Reads as $profile"
check ok "ec2 describe-availability-zones" -- aws ec2 describe-availability-zones "${p[@]}"
check ok "cloudformation list-stacks" -- aws cloudformation list-stacks --max-items 5 "${p[@]}"
check ok "logs describe-log-groups" -- aws logs describe-log-groups --limit 1 "${p[@]}"
check ok "lambda list-functions (REST GET)" -- aws lambda list-functions --max-items 1 "${p[@]}"
check ok "ecs list-clusters" -- aws ecs list-clusters "${p[@]}"
check ok "ssm describe-parameters" -- aws ssm describe-parameters --max-results 1 "${p[@]}"
check ok "s3api list-buckets" -- aws s3api list-buckets "${p[@]}"
check ok "iam list-roles (global endpoint)" -- aws iam list-roles --max-items 1 "${p[@]}"
check ok "route53 list-hosted-zones (global REST)" -- aws route53 list-hosted-zones --max-items 1 "${p[@]}"
check ok "ec2 describe-availability-zones in us-east-1 (any region passes nono)" -- aws ec2 describe-availability-zones --region us-east-1 "${p[@]}"
if [ -n "$bucket" ]; then
  check ok "s3 ls s3://$bucket (virtual-hosted)" -- aws s3 ls "s3://$bucket" "${p[@]}"
  check ok "s3api list-objects-v2 path-style" -- aws s3api list-objects-v2 --bucket "$bucket" --max-keys 1 --endpoint-url "https://s3.${AWS_REGION:-eu-west-1}.amazonaws.com" "${p[@]}"
fi

echo "== Writes: nono refuses before AWS sees them"
check nono "sts assume-role" -- aws sts assume-role --role-arn arn:aws:iam::000000000000:role/nono-battle --role-session-name nono-battle "${p[@]}"
check nono "ec2 terminate-instances --dry-run" -- aws ec2 terminate-instances --instance-ids i-00000000000000000 --dry-run "${p[@]}"
check nono "sqs delete-queue (no such queue)" -- aws sqs delete-queue --queue-url "https://sqs.${AWS_REGION:-eu-west-1}.amazonaws.com/000000000000/nono-battle" "${p[@]}"
check nono "ssm delete-parameter (no such parameter)" -- aws ssm delete-parameter --name /nono-battle/none "${p[@]}"
check nono "dynamodb scan (no such table)" -- aws dynamodb scan --table-name nono-battle-none "${p[@]}"
check nono "lambda invoke (REST POST)" -- aws lambda invoke --function-name nono-battle-none /dev/null "${p[@]}"
check nono "s3api put-object (REST PUT, no such bucket)" -- aws s3api put-object --bucket "nono-battle-none-$$" --key x --body /dev/null "${p[@]}"
check nono "iam delete-user (global, no such user)" -- aws iam delete-user --user-name nono-battle-none "${p[@]}"
check nono "cloudformation delete-stack (no such stack)" -- aws cloudformation delete-stack --stack-name nono-battle-none "${p[@]}"

echo "== Data reads: nono passes them (Get*), the readonly policy refuses"
check iam "secretsmanager get-secret-value" -- aws secretsmanager get-secret-value --secret-id nono-battle-none "${p[@]}"
check iam "ssm get-parameter --with-decryption" -- aws ssm get-parameter --name /nono-battle/none --with-decryption "${p[@]}"
check iam "logs get-log-events" -- aws logs get-log-events --log-group-name nono-battle --log-stream-name none "${p[@]}"
check iam "dynamodb get-item" -- aws dynamodb get-item --table-name nono-battle-none --key '{"id":{"S":"x"}}' "${p[@]}"
check iam "lambda get-function (environment variables)" -- aws lambda get-function --function-name nono-battle-none "${p[@]}"
[ -n "$bucket" ] &&
  check iam "s3api get-object" -- aws s3api get-object --bucket "$bucket" --key nono-battle-none /dev/null "${p[@]}"

if $interactive; then
  echo "== A service with no route (approval prompt in your tuios pane)"
  echo "   Answer \"Allow once\": the request then reaches AWS unsigned, and must fail there."
  check unsigned "athena list-work-groups, allowed once" -- aws athena list-work-groups "${p[@]}"
  echo "   Now answer \"Deny\"."
  check nono "athena list-work-groups, denied" -- aws athena list-work-groups "${p[@]}"
fi

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
