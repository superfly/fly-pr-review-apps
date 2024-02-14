# PR Review Apps on Fly.io

This GitHub action wraps the Fly.io CLI to automatically deploy pull requests to [fly.io](http://fly.io) for review. These are useful for testing changes on a branch without having to setup explicit staging environments.

This action will create, deploy, and destroy Fly apps. Just set an Action Secret for `FLY_API_TOKEN`.

If you have an existing `fly.toml` in your repo, this action will copy it with a new name when deploying. By default, Fly apps will be named with the scheme `{repo_name}-pr-{number}`.

## Inputs

| name       | description                                                                                                                                                                                              |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `name`     | The name of the Fly app. Alternatively, set the env `FLY_APP`. For safety, must include the PR number. Example: `myapp-pr-${{ github.event.number }}`. Defaults to `{repo_name}-pr-{number}`. |                           |
| `region`   | Which Fly region to run the app in. Alternatively, set the env `FLY_REGION`. Defaults to `iad`.                                                                                                          |
| `org`      | Which Fly organization to launch the app under. Alternatively, set the env `FLY_ORG`. Defaults to `personal`.                                                                                            |
| `path`     | Path to run the `flyctl` commands from. Useful if you have an existing `fly.toml` in a subdirectory.                                                                                                     |
| `postgres` | Optional name of an existing Postgres cluster to `flyctl postgres attach` to.                                                                                                                            |                                                                                                                                  |                                                                                                                                       |                                                                                                                                                       |
| `dockerfile`       | Path to a Dockerfile, that will be used for building the image                                                                                                                             |

## Required Secrets

`FLY_API_TOKEN` - **Required**. The token to use for authentication. You can find a token by running `flyctl auth token` or going to your [user settings on fly.io](https://fly.io/user/personal_access_tokens).

Note: If you have a team or organization account create a org token and set the value in `FLY_API_TOKEN`.

## Basic Example

```yaml
name: Preview App

on:
  pull_request:
    types: [opened, reopened, synchronize, closed]

env:
  FLY_API_TOKEN: ${{ secrets.FLY_ORG_TOKEN }}
  FLY_REGION: <your region>
  FLY_ORG: <your org>

jobs:
  staging_app:
    runs-on: ubuntu-latest

    # Only run one deployment at a time per PR.
    concurrency:
      group: pr-${{ github.event.number }}

    # Create a GitHub deployment environment per staging app so it shows up
    # in the pull request UI.
    environment:
      name: pr-${{ github.event.number }}
      url: ${{ steps.deploy.outputs.url }}

    steps:
      - uses: actions/checkout@v4

      - uses: superfly/flyctl-actions/setup-flyctl@master

      - name: Deploy
        id: deploy
        uses: superfly/fly-pr-review-apps@main
        with:
          dockerfile: ./Dockerfile

      - name: Set secrets in Fly
        if: ${{ github.event.action == 'opened' || github.event.action == 'reopened' || github.event.action == 'synchronize' }}
        run: |
          flyctl secrets set -a yourapp-pr-${{ github.event.number }} \
          EXAMPLE_SECRET=${{ secrets.EXAMPLE_SECRET }} \

      - name: Update image
        if: ${{ github.event.action == 'opened' || github.event.action == 'reopened' || github.event.action == 'synchronize' }}
        run: flyctl image update -a yourapp-pr-${{ github.event.number }} --skip-health-checks -y
```

## Cleaning up GitHub environments

This action will destroy the Fly app, but it will not destroy the GitHub environment, so those will hang around in the GitHub UI. If this is bothersome, use an action like `strumwolf/delete-deployment-environment` to delete the environment when the PR is closed.

```yaml
on:
  pull_request:
    types: [opened, reopened, synchronize, closed]

# ...

jobs:
  staging_app:
    # ...

    # Create a GitHub deployment environment per review app.
    environment:
      name: pr-${{ github.event.number }}
      url: ${{ steps.deploy.outputs.url }}

    steps:
      - uses: actions/checkout@v4

      - name: Deploy app
        id: deploy
        uses: superfly/fly-pr-review-apps@1.0.0

      - name: Clean up GitHub environment
        uses: strumwolf/delete-deployment-environment@v2
        if: ${{ github.event.action == 'closed' }}
        with:
          # ⚠️ The provided token needs permission for admin write:org
          token: ${{ secrets.GITHUB_TOKEN }}
          environment: pr-${{ github.event.number }}
```

## Example with Postgres cluster

If you have an existing [Fly Postgres cluster](https://fly.io/docs/reference/postgres/) you can attach it using the `postgres` action input. `flyctl postgres attach` will be used, which automatically creates a new database in the cluster named after the Fly app and sets `DATABASE_URL`.

For production apps, it's a good idea to create a new Postgres cluster specifically for staging apps.

```yaml
# ...
steps:
  - uses: actions/checkout@v4

  - name: Deploy app
    id: deploy
    uses: superfly/fly-pr-review-apps@1.0.0
    with:
      postgres: <your-existing-preview-db>
```

## Example with multiple Fly apps

If you need to run multiple Fly apps per staging app, for example Redis, memcached, etc, just give each app a unique name. Your application code will need to be able to discover the app hostnames.

Redis example:

```yaml
steps:
  - uses: actions/checkout@v4

  - name: Deploy redis
    uses: superfly/fly-pr-review-apps@1.0.0
    with:
      update: false # Don't need to re-deploy redis when the PR is updated
      path: redis # Keep fly.toml in a subdirectory to avoid confusing flyctl
      image: flyio/redis:6.2.6
      name: pr-${{ github.event.number }}-myapp-redis

  - name: Deploy app
    id: deploy
    uses: superfly/fly-pr-review-apps@1.0.0
    with:
      name: pr-${{ github.event.number }}-myapp-app
```
