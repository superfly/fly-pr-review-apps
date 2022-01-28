#!/bin/sh -l

set -ex

if [ -n "$INPUT_PATH" ]; then
  # Allow user to change directories in which to run Fly commands.
  cd "$INPUT_PATH" || exit
fi

# PR_NUMBER=$(echo "$GITHUB_REF" | awk 'BEGIN { FS = "/" } ; { print $3 }')
EVENT_TYPE=$(jq -r .action /github/workflow/event.json)

app="$INPUT_NAME" # TODO: default this to something based on repo+PR_NUMBER
region="${INPUT_REGION:-${FLY_REGION:-iad}}"
org="${INPUT_ORG:-${FLY_ORG:-personal}}"
image="$INPUT_IMAGE"

# PR was opened or reopened.
if [ "$EVENT_TYPE" = "opened" ] || [ "$EVENT_TYPE" = "reopened" ]; then

  # Create the Fly app.
  flyctl launch --now --copy-config --name "$app" --image "$image" --region "$region" --org "$org"

  # Attach postgres cluster to the new app if needed.
  if [ -n "$INPUT_POSTGRES" ]; then
    flyctl postgres attach --postgres-app "$INPUT_POSTGRES"
  fi

# New commits were added to the PR, and this is an app we want to deploy.
elif [ "$EVENT_TYPE" = "synchronize" ] && [ "$INPUT_UPDATE" != "false" ]; then

  # Deploy the Fly app.
  flyctl deploy --app "$app"

fi

# Output the app URL to make it available to the GitHub workflow.
url=$(fly info --json | jq -r .App.AppURL) || true
if [ -n "$url" ]; then
  echo "::set-output name=url::$url"
fi

# PR was closed - remove the Fly app.
if [ "$EVENT_TYPE" = "closed" ]; then
  flyctl apps destroy "$app" -y
fi
