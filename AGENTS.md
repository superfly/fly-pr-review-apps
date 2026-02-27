# AGENTS.md

## Purpose

This repository provides a Docker-based GitHub Action that deploys temporary Fly.io review apps for pull requests and destroys them when pull requests close.

## Repository Map

- `action.yml` - Action metadata and inputs.
- `Dockerfile` - Runtime image with `flyctl`, `jq`, and `curl`.
- `entrypoint.sh` - Core logic (create/deploy/destroy and outputs).
- `README.md` - User-facing docs and examples.
- `bump-version.sh` - Semantic version tag helper.

## Behavioral Contract

1. Read pull request metadata from `/github/workflow/event.json`.
2. Require the pull request number in the app name as a safety guard.
3. On `pull_request.closed`, destroy the Fly app and exit cleanly.
4. Otherwise, create app if missing, apply optional secrets/postgres, deploy, and emit outputs.

## Change Rules

- Keep scripts compatible with Alpine `/bin/sh` where applicable.
- If inputs/outputs change, update all of:
  - `action.yml`
  - `entrypoint.sh`
  - `README.md`
- Never log secrets.
- Preserve the pull-request-number app-name safety check.
- Do not add co-authors to commit messages.
- For any code change, always create a branch and open a pull request.

## Verification

- `docker build -t fly-pr-review-apps .`
- `shellcheck entrypoint.sh bump-version.sh` (if available)
- Ensure docs match behavior and inputs/outputs.
