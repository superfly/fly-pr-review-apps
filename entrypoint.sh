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

GITHUB_REPOSITORY_NAME=${GITHUB_REPOSITORY#$GITHUB_REPOSITORY_OWNER/}
EVENT_TYPE=$INPUT_EVENT_ACTION

# Default the Fly app name to pr-{number}-{repo_owner}-{repo_name}
app="${INPUT_NAME:-pr-$PR_NUMBER-$GITHUB_REPOSITORY_OWNER-$GITHUB_REPOSITORY_NAME}"
# Change underscores to hyphens and slashes to hyphens.
app=$(echo "$app" | sed 's/_/-/g' | sed 's/\//-/g')
region="${INPUT_REGION:-${FLY_REGION:-iad}}"
org="${INPUT_ORG:-${FLY_ORG:-personal}}"
image="$INPUT_IMAGE"
config="${INPUT_CONFIG:-fly.toml}"
build_args=""
build_secrets=""
runtime_environment=""
database_name="${app/-/_}_pg"
database_role="${app/-/_}_pg"

if ! echo "$app" | grep "$PR_NUMBER"; then
  if [ "$INPUT_ALLOW_UNSAFE_NAME" != "true" ]; then
    echo "For safety, this action requires the app's name to contain the PR number. If you are sure you want to proceed, set the 'allow_unsafe_name' input to 'true'."
    exit 1
  fi
  echo "WARNING: The app's name does not contain the PR number. it is recommended to include the PR number in the app's name."
fi

# PR was closed - remove the Fly app if one exists and exit.
if [ "$EVENT_TYPE" = "closed" ]; then
  flyctl apps destroy "$app" -y || true

  if [ "$INPUT_POSTGRES_CLEAN_ON_CLOSE" == "true" && -n "$INPUT_POSTGRES" ]; then
    flyctl postgres connect --app "$INPUT_POSTGRES" <<EOF || true
      drop database ${database_name} with (force );
      drop role ${database_role};
      \q
EOF
  fi

  exit 0
fi

#from https://github.com/superfly/fly-pr-review-apps/pull/50
# FIXME spaces, maybe split by \D+=
if [ -n "$INPUT_BUILD_ARGS" ]; then
  for ARG in $(echo "$INPUT_BUILD_ARGS" | tr " " "\n"); do
    build_args="$build_args --build-arg ${ARG}"
  done
fi

if [ -n "$INPUT_BUILD_SECRETS" ]; then
  for ARG in $(echo "$INPUT_BUILD_SECRETS" | tr " " "\n"); do
    build_secrets="$build_secrets --build-secret ${ARG}"
  done
fi

if [ -n "$INPUT_ENVIRONMENT" ]; then
  for ARG in $(echo "$INPUT_ENVIRONMENT" | sed 's/\b\(\w\+\)=/\n\1=/g'); do
    runtime_environment="$runtime_environment --env ${ARG}"
  done
fi

# Deploy the Fly app, creating it first if needed.
if ! flyctl status --app "$app"; then
  if [ -n "$INPUT_CONFIG" ]; then
    # Config specified explicitly, create empty app
    flyctl app create --name "$app" --org "$org"
  else
    # Default behavior: launch the app inplace from default config
    # TODO: https://github.com/superfly/fly-pr-review-apps/issues/49
    #  Probably dont need to use launch for preview at all or adjust to launch only (handle redis/postgres deletion on destroy)

    # Backup the original config file since 'flyctl launch' messes up the [build.args] section
    cp "$config" "$config.bak"
    flyctl launch --no-deploy --copy-config --name "$app" --image "$image" --region "$region" --org "$org" ${build_args} ${build_secrets} ${runtime_environment}
    # Restore the original config file
    cp "$config.bak" "$config"
  fi
fi
if [ -n "$INPUT_SECRETS" ]; then
  echo $INPUT_SECRETS | tr " " "\n" | flyctl secrets import --app "$app"
fi

# Attach postgres cluster to the app if specified.
if [ -n "$INPUT_POSTGRES" ]; then
  flyctl postgres attach "$INPUT_POSTGRES" --app "$app" --database-name "$database_name" --database-user "$database_role" || true
fi

# Use remote builders
if [ -n "$INPUT_REMOTE_ONLY" ]; then
  remote_only="--remote-only"
fi

# Trigger the deploy of the new version.
echo "Contents of config $config file: " && cat "$config"
if [ -n "$INPUT_VM" ]; then
  flyctl deploy --config "$config" --app "$app" --regions "$region" --image "$image" --strategy immediate --ha=$INPUT_HA ${build_args} ${build_secrets} ${runtime_environment} ${remote_only} --vm-size "$INPUT_VMSIZE"
else
  flyctl deploy --config "$config" --app "$app" --regions "$region" --image "$image" --strategy immediate --ha=$INPUT_HA ${build_args} ${build_secrets} ${runtime_environment} ${remote_only} --vm-cpu-kind "$INPUT_CPUKIND" --vm-cpus $INPUT_CPU --vm-memory "$INPUT_MEMORY"
fi

# Make some info available to the GitHub workflow.
flyctl status --app "$app" --json >status.json
hostname=$(jq -r .Hostname status.json)
appid=$(jq -r .ID status.json)
echo "hostname=$hostname" >> $GITHUB_OUTPUT
echo "url=https://$hostname" >> $GITHUB_OUTPUT
echo "id=$appid" >> $GITHUB_OUTPUT
echo "name=$app" >> $GITHUB_OUTPUT
