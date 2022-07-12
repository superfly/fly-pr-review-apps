#!/bin/bash -l

set -ex

if [ -n "$INPUT_PATH" ]; then
  # Allow user to change directories in which to run Fly commands.
  cd "$INPUT_PATH" || exit
fi

PR_NUMBER=$(jq -r .number /github/workflow/event.json)
if [ -z "$PR_NUMBER" ]; then
  echo "This action only supports pull_request actions."
  exit 1
fi

REPO_OWNER=$(jq -r .organization.login /github/workflow/event.json)
REPO_NAME=$(jq -r .repository.name /github/workflow/event.json)
EVENT_TYPE=$(jq -r .action /github/workflow/event.json)

# Default the Fly app name to pr-{number}-{repo_owner}-{repo_name}
app="${INPUT_NAME:-pr-$PR_NUMBER-$REPO_OWNER-$REPO_NAME}"
postgres_app="${INPUT_POSTGRES_NAME:-pr-$PR_NUMBER-$REPO_OWNER-$REPO_NAME-postgres}"
region="${INPUT_REGION:-${FLY_REGION:-cdg}}"
org="${INPUT_ORG:-${FLY_ORG:-personal}}"
image="$INPUT_IMAGE"
postgres_vm_size="${INPUT_POSTGRES_VM_SIZE:-shared-cpu-1x}"

if ! echo "$app" | grep "$PR_NUMBER"; then
  echo "For safety, this action requires the app's name to contain the PR number."
  exit 1
fi

# PR was closed - remove the Fly app if one exists and exit.
if [ "$EVENT_TYPE" = "closed" ]; then
  flyctl apps destroy "$app" -y || true
  if [ -n "$INPUT_POSTGRES" ]; then
    flyctl apps destroy "$postgres_app" -y || true
  fi
  exit 0
fi

# Deploy the Fly app, creating it first if needed.
if ! flyctl status --app "$app"; then
  flyctl apps create --name "$app" --org "$org"
fi

# Attach postgres cluster to the app if specified.
if [ -n "$INPUT_POSTGRES" ]; then
  if ! flyctl status --app "$postgres_app"; then
    flyctl postgres create --name "$postgres_app" --region "$region" --organization "$org" --vm-size "$postgres_vm_size" --volume-size 1 --initial-cluster-size 1 || true
    flyctl postgres attach --app "$app" --postgres-app "$postgres_app" || true
  fi
fi

if [ -n "$INPUT_SECRETS" ]; then
  bash -c "fly secrets --app $app set $(for secret in $(echo $INPUT_SECRETS | tr ";" "\n") ; do
    value="${secret}"
    echo -n " $secret='${!value}' "
  done)" || true
fi

if [ "$INPUT_UPDATE" != "false" ]; then
  flyctl deploy --app "$app" --region "$region" --image "$image" --region "$region" --strategy immediate
fi


# Make some info available to the GitHub workflow.
fly status --app "$app" --json >status.json
hostname=$(jq -r .Hostname status.json)
appid=$(jq -r .ID status.json)
echo "::set-output name=hostname::$hostname"
echo "::set-output name=url::https://$hostname"
echo "::set-output name=id::$appid"
