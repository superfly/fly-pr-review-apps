# PR review apps on Fly.io

This GitHub action allows new pull requests to automatically deploy PR-specific "review apps" to Fly.io. These are useful for testing changes on a branch without having to set up explicit feature or bug-fix environments. This action will create, update, and eventually destroy Fly apps for each PR.

For more detailed instructions about this process, check out [Review Apps on Fly.io](https://fly.io/docs/app-guides/review-apps-guide) in our docs.

## Getting Started

Using this Github action, you can use setup review apps for your Fly application in three steps:

1. Create a new repository secret on your GitHub repository called `FLY_API_TOKEN` and provide it with the returned value of `fly auth token`
1. Create a new workflow in your project at `.github/workflows/fly-review.yml` and add the following [YAML code](https://gist.github.com/anniebabannie/3cb800f2a890a6f3ed3167c09a0234dd).
1. Commit and push the changes containing your GitHub workflow.

And that's it! The workflow described above will spin up a **single application** without other resources. If datastores, multiple Fly Apps, or other resources are required, see [Customizing your workflow](#customize-your-workflow).

If you have an existing `fly.toml` in your repo, this action will copy it with a new name when deploying. By default, Fly apps will be named with the scheme `pr-{number}-{repo_org}-{repo_name}`.

## Inputs


| name       | description                                                                                                                                                                                              |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `name`     | The name of the Fly app. Alternatively, set the env `FLY_APP`. For safety, it **must include the PR number**. Example: `myapp-pr-${{ github.event.number }}`. Defaults to `pr-{number}-{repo_org}-{repo_name}`. |
| `image`    | Optional pre-existing Docker image to use                                                                                                                                                                |
| `config`   | Optional path to a custom Fly toml config. Config path should be relative to `path` parameter, if specified.                                                                                             |
| `region`   | Which Fly region to run the app in. Alternatively, set the env `FLY_REGION`. Defaults to `iad`.                                                                                                          |
| `org`      | Which Fly organization to launch the app under. Alternatively, set the env `FLY_ORG`. Defaults to `personal`.                                                                                            |
| `path`     | Path to run the `flyctl` commands from. Useful if you have an existing `fly.toml` in a subdirectory.                                                                                                     |
| `postgres` | Optional name of an existing Postgres cluster to `flyctl postgres attach` to.                                                                                                                            |
| `update`   | Whether or not to update this Fly app when the PR is updated. Default `true`.                                                                                                                            |
| `secrets`  | Secrets to be set on the app, formatted as `MY_ENV_VAR=value` and separated by a space.                                                                                                                                     |
| `vmsize`   | Set app VM to a named size, eg. shared-cpu-1x, dedicated-cpu-1x, dedicated-cpu-2x etc. Takes precedence over cpu, cpu kind, and memory inputs.                                                           |
| `cpu`      | Set app VM CPU (defaults to 1 cpu). Default 1.                                                                                                                                                           |
| `cpukind`  | Set app VM CPU kind - shared or performance. Default shared.                                                                                                                                             |
| `memory`   | Set app VM memory in megabytes. Default 256.                                                                                                                                                             |
| `ha`       | Create spare machines that increases app availability. Default `false`.                                                                                                                                  |


Customize your workflow by adding the inputs to the step that uses this (**superfly/fly-pr-review-apps**) Github action, like so:

```yaml
# fly-review.yml
# ...
    steps:
      # ...
      - name: Deploy PR app to Fly.io
        id: deploy
        uses: superfly/fly-pr-review-apps@1.2.0
        with:
          name: my-app-name-pr-${{ github.event.number }}
          config: fly.review.toml
```

## Required Secrets

`FLY_API_TOKEN` - **Required**. The token to use for authentication. You can find a token by running `flyctl auth token` or going to your [user settings on fly.io](https://fly.io/user/personal_access_tokens). Once obtained, add this as a repository secret in GitHub.

## Basic example

```yaml
name: Deploy Review App
on:
  # Run this workflow on every PR event. Existing review apps will be updated when the PR is updated.
  pull_request:
    types: [opened, reopened, synchronize, closed]

env:
  FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
  # Set these to your Fly.io organization and preferred region.
  FLY_REGION: iad
  FLY_ORG: personal

jobs:
  review_app:
    runs-on: ubuntu-latest
    outputs:
      url: ${{ steps.deploy.outputs.url }}
    # Only run one deployment at a time per PR.
    concurrency:
      group: pr-${{ github.event.number }}

    # Deploying apps with this "review" environment allows the URL for the app to be displayed in the PR UI.
    # Feel free to change the name of this environment.
    environment:
      name: review
      # The script in the `deploy` sets the URL output for each review app.
      url: ${{ steps.deploy.outputs.url }}

    steps:
      - name: Get code
        uses: actions/checkout@v4

      - name: Deploy PR app to Fly.io
        id: deploy
        uses: superfly/fly-pr-review-apps@1.2.0
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
      postgres: myapp-postgres-staging-apps
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
