#!/bin/ash -l
# shellcheck shell=dash

set -e

if [ -n "$INPUT_PATH" ]; then
  # Allow user to change directories in which to run Fly commands.
  cd "$INPUT_PATH" || exit
fi

PR_NUMBER=$(jq -r .number /github/workflow/event.json)
if [ -z "$PR_NUMBER" ]; then
  echo "This action only supports pull_request actions."
  exit 1
fi

GITHUB_REPOSITORY_NAME=${GITHUB_REPOSITORY#"$GITHUB_REPOSITORY_OWNER"/}
EVENT_TYPE=$(jq -r .action /github/workflow/event.json)

# Default the Fly app name to pr-{number}-{repo_owner}-{repo_name}
app="${INPUT_NAME:-pr-$PR_NUMBER-$GITHUB_REPOSITORY_OWNER-$GITHUB_REPOSITORY_NAME}"
# Change underscores to hyphens.
# shellcheck disable=SC3060
app="${app//_/-}"
region="${INPUT_REGION:-${FLY_REGION:-iad}}"
org="${INPUT_ORG:-${FLY_ORG:-personal}}"
image="$INPUT_IMAGE"
config="${INPUT_CONFIG:-fly.toml}"

if ! printf '%s' "$app" | grep -q "$PR_NUMBER"; then
  echo "For safety, this action requires the app's name to contain the PR number."
  exit 1
fi

# PR was closed - remove the Fly app if one exists and exit.
if [ "$EVENT_TYPE" = "closed" ]; then
  flyctl apps destroy "$app" -y || true
  exit 0
fi

# Deploy the Fly app, creating it first if needed.
if ! flyctl status --app "$app"; then
  # Backup the original config file since 'flyctl launch' messes up the [build.args] section
  cp "$config" "$config.bak"
  set -- flyctl launch --no-deploy --copy-config --name "$app" --image "$image" --region "$region" --org "$org"
  if [ -n "$INPUT_BUILD_ARGS" ]; then
    for ARG in $INPUT_BUILD_ARGS; do
      set -- "$@" --build-arg "$ARG"
    done
  fi
  if [ -n "$INPUT_BUILD_SECRETS" ]; then
    for ARG in $INPUT_BUILD_SECRETS; do
      set -- "$@" --build-secret "$ARG"
    done
  fi
  if [ -n "$INPUT_LAUNCH_OPTIONS" ]; then
    # shellcheck disable=SC2086
    set -- "$@" $INPUT_LAUNCH_OPTIONS
  fi
  "$@"
  # Restore the original config file
  cp "$config.bak" "$config"
fi

if [ -n "$INPUT_SECRETS" ]; then
  printf '%s\n' "$INPUT_SECRETS" | tr " " "\n" | flyctl secrets import --app "$app"
fi

# Attach postgres cluster to the app if specified.
if [ -n "$INPUT_POSTGRES" ]; then
  flyctl postgres attach "$INPUT_POSTGRES" --app "$app" || true
fi

# Trigger the deploy of the new version.
echo "Contents of config $config file: " && cat "$config"
if [ -n "$INPUT_VMSIZE" ]; then
  set -- flyctl deploy --config "$config" --app "$app" --regions "$region" --image "$image" --strategy immediate --ha="$INPUT_HA" --vm-size "$INPUT_VMSIZE"
  if [ -n "$INPUT_BUILD_ARGS" ]; then
    for ARG in $INPUT_BUILD_ARGS; do
      set -- "$@" --build-arg "$ARG"
    done
  fi
  if [ -n "$INPUT_BUILD_SECRETS" ]; then
    for ARG in $INPUT_BUILD_SECRETS; do
      set -- "$@" --build-secret "$ARG"
    done
  fi
  if [ -n "$INPUT_DEPLOY_OPTIONS" ]; then
    # shellcheck disable=SC2086
    set -- "$@" $INPUT_DEPLOY_OPTIONS
  fi
  "$@"
else
  set -- flyctl deploy --config "$config" --app "$app" --regions "$region" --image "$image" --strategy immediate --ha="$INPUT_HA" --vm-cpu-kind "$INPUT_CPUKIND" --vm-cpus "$INPUT_CPU" --vm-memory "$INPUT_MEMORY"
  if [ -n "$INPUT_BUILD_ARGS" ]; then
    for ARG in $INPUT_BUILD_ARGS; do
      set -- "$@" --build-arg "$ARG"
    done
  fi
  if [ -n "$INPUT_BUILD_SECRETS" ]; then
    for ARG in $INPUT_BUILD_SECRETS; do
      set -- "$@" --build-secret "$ARG"
    done
  fi
  if [ -n "$INPUT_DEPLOY_OPTIONS" ]; then
    # shellcheck disable=SC2086
    set -- "$@" $INPUT_DEPLOY_OPTIONS
  fi
  "$@"
fi

# Make some info available to the GitHub workflow.
flyctl status --app "$app" --json >status.json
hostname=$(jq -r .Hostname status.json)
appid=$(jq -r .ID status.json)
{
  echo "hostname=$hostname"
  echo "url=https://$hostname"
  echo "id=$appid"
  echo "name=$app"
} >>"$GITHUB_OUTPUT"
