#!/bin/sh -l

set -ex

if [ -n "$INPUT_PATH" ]; then
  # Allow user to change directories in which to run Fly commands.
  cd "$INPUT_PATH" || exit
fi

PR_NUMBER=$(jq -r .number /github/workflow/event.json)
REPO_OWNER=$(jq -r .event.base.repo.owner /github/workflow/event.json)
REPO_NAME=$(jq -r .event.base.repo.name /github/workflow/event.json)
EVENT_TYPE=$(jq -r .action /github/workflow/event.json)

# Default the Fly app name to pr-{number}-{repo_owner}-{repo_name}
app="${INPUT_NAME:-pr-$PR_NUMBER-$REPO_OWNER-$REPO_NAME}"

region="${INPUT_REGION:-${FLY_REGION:-iad}}"
org="${INPUT_ORG:-${FLY_ORG:-personal}}"
image="$INPUT_IMAGE"

deployed=$(fly status --app "$app" --json | jq -r .Deployed) || true

# PR was opened or reopened, or the Fly app hasn't been successfully created yet.
if [ "$deployed" != "true" ] || [ "$EVENT_TYPE" = "opened" ] || [ "$EVENT_TYPE" = "reopened" ]; then

  # Create the Fly app.
  flyctl launch --now --copy-config --name "$app" --image "$image" --region "$region" --org "$org"

  # Attach postgres cluster to the new app if needed.
  if [ -n "$INPUT_POSTGRES" ]; then
    flyctl postgres attach --postgres-app "$INPUT_POSTGRES"
  fi

# New commits were added to the PR, and this is an app we want to re-deploy when the PR is updated.
elif [ "$EVENT_TYPE" = "synchronize" ] && [ "$INPUT_UPDATE" != "false" ]; then

  # Deploy the Fly app.
  flyctl deploy --app "$app"

fi

# Output the app URL to make it available to the GitHub workflow.
hostname=$(fly status --app "$app" --json | jq -r .App.Hostname) || true
if [ -n "$hostname" ]; then
  echo "::set-output name=url::https://$hostname"
fi

# PR was closed - remove the Fly app.
if [ "$EVENT_TYPE" = "closed" ]; then
  flyctl apps destroy "$app" -y
fi
