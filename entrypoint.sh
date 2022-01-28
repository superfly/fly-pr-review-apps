#!/bin/sh -l

set -ex

if [ -n "$INPUT_PATH" ]; then
  # Allow user to change directories in which to run Fly commands
  cd "$INPUT_PATH" || exit
fi

PR_NUMBER=$(echo "$GITHUB_REF" | awk 'BEGIN { FS = "/" } ; { print $3 }')
EVENT_TYPE=$(jq -r .action /github/workflow/event.json)

app="$INPUT_NAME-pr$PR_NUMBER"
region="${INPUT_REGION:-${FLY_REGION:-iad}}"
org="${INPUT_ORG:-${FLY_ORG:-personal}}"

# PR was opened or reopened
if [ "$EVENT_TYPE" = "opened" ] || [ "$EVENT_TYPE" = "reopened" ]; then

  flyctl launch --now --name "$app" --region "$region" --org "$org" --copy-config

  # Attach postgres cluster to the new app if needed
  if [ -n "$INPUT_POSTGRES" ]; then
    flyctl postgres attach --postgres-app "$INPUT_POSTGRES"
  fi

# New commits were added to the PR, and this is an app we want to deploy
elif [ "$EVENT_TYPE" = "synchronize" ] && [ "$INPUT_UPDATE" != "false" ]; then

  flyctl deploy --app "$app"

# PR was closed
elif [ "$EVENT_TYPE" = "closed" ]; then

  flyctl apps destroy "$app" -y

fi
