#!/bin/sh -l

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

REPO_NAME=$(echo $GITHUB_REPOSITORY | tr "/" "-")
EVENT_TYPE=$(jq -r .action /github/workflow/event.json)

# Default the Fly app name to pr-{number}-{repo_name}
app="${INPUT_NAME:-pr-$PR_NUMBER-$REPO_NAME}"
region="${INPUT_REGION:-${FLY_REGION:-iad}}"
org="${INPUT_ORG:-${FLY_ORG:-personal}}"
image="$INPUT_IMAGE"
config="${INPUT_CONFIG:-fly.toml}"
database="${INPUT_DATABASE:-$app}"

if ! echo "$app" | grep "$PR_NUMBER"; then
  echo "For safety, this action requires the app's name to contain the PR number."
  exit 1
fi

# PR was closed - remove the Fly app if one exists and exit.
if [ "$EVENT_TYPE" = "closed" ]; then
  if [ -n "$INPUT_POSTGRES" ]; then
    apk add expect

    # Detach app from postgres cluster and database.
    expect -c "
      spawn flyctl postgres detach "$INPUT_POSTGRES" --app "$app"
      expect {Select the attachment that you would like to detach*}
      send -- \"\r\"
      expect eof
    "
  fi

  # Destroy the Fly app
  flyctl apps destroy "$app" -y || true
  exit 0
fi

# Backup the original config file since 'flyctl launch' messes up the [build.args] section
cp "$config" "$config.bak"

# Deploy the Fly app, creating it first if needed.
if ! flyctl status --app "$app"; then
  # Install elixir
  apk add elixir
  apk add inotify-tools
  mix local.hex --force
  mix local.rebar --force

  # Launch new app
  flyctl launch --no-deploy --copy-config --name "$app" --region "$region" --org "$org" --remote-only --ha=false || true
fi

# Get list of secrets
secrets=$(flyctl secrets -a "$app" list)

if ! echo "$secrets_output" | grep -q "PHX_HOST"; then
  # Add app host to env secrets
  flyctl secrets set --app "$app" PHX_HOST="$app".fly.dev
fi

if ! echo "$secrets" | grep -q "DATABASE_URL"; then
  if [ -n "$INPUT_POSTGRES" ]; then
    # Replace - with _ in app name to get postgres user name
    postgres_user="${app//-/_}"

    # Execute DROP USER command using flyctl postgres connect
    eval "flyctl postgres connect -a "$INPUT_POSTGRES" <<EOF
    \c $database;
    REASSIGN OWNED BY $postgres_user TO postgres;
    DROP OWNED BY $postgres_user;
    DROP USER $postgres_user;
    \q
    EOF"

    # Attach app to postgres cluster and database.
    flyctl postgres attach --app "$app" "$INPUT_POSTGRES" --database-name "$database" --yes || true
  fi
fi

# Restore the original config file
cp "$config.bak" "$config"

if [ -n "$INPUT_SECRETS" ]; then
  echo $INPUT_SECRETS | tr " " "\n" | flyctl secrets import --app "$app"
fi

# Deploy app
flyctl deploy --config "$config" --app "$app" --region "$region" --image "$image" --strategy immediate

# Scale the VM
if [ -n "$INPUT_VM" ]; then
  flyctl scale --app "$app" vm "$INPUT_VM"
fi

if [ -n "$INPUT_MEMORY" ]; then
  flyctl scale --app "$app" memory "$INPUT_MEMORY"
fi

if [ -n "$INPUT_COUNT" ]; then
  flyctl scale --app "$app" count "$INPUT_COUNT"
fi

# Make some info available to the GitHub workflow.
flyctl status --app "$app" --json >status.json
hostname=$(jq -r .Hostname status.json)
appid=$(jq -r .ID status.json)
echo "hostname=$hostname" >> $GITHUB_OUTPUT
echo "url=https://$hostname" >> $GITHUB_OUTPUT
echo "id=$appid" >> $GITHUB_OUTPUT
echo "name=$app" >> $GITHUB_OUTPUT
