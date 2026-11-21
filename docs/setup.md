# Setup

What a repository needs before the sync can run in it. The [workflow](../.github/workflows/docs-sync.yaml) in this
repository is the example to copy.

## The workflow

The workflow owns what the action cannot: the timer, the manual trigger, the concurrency group and the credential.

- Check out with full history (`fetch-depth: 0`). The sync reads the cursor from the history.
- Use one concurrency group and do not cancel runs in progress, so that two runs never replay at the same time.
- Run it once with mode `reset-to-other` before the first sync.

The action's inputs are described in [action.yml](../.github/actions/docs-sync/action.yml).

## Pushing to a protected branch

Replayed commits must reach the branch one by one, with their messages intact. A branch that only takes squash-merged
pull requests does not allow that, so the sync needs a credential that may bypass the branch rules. A push with the
workflow's own `GITHUB_TOKEN` cannot bypass them, and does not start other workflows either.

### With a GitHub App

This is what the trial runs with.

1. Create a GitHub App with the repository permission Contents: Read and write, and no webhook.
2. Install it on the repository.
3. Store its client ID as the repository variable `DOC_SYNC_APP_CLIENT_ID`.
4. Create an environment named `docs-sync` that only the default branch may deploy to. Store the app's private key
   there as the secret `DOC_SYNC_APP_PRIVATE_KEY`.
5. Add the app to the bypass list of the ruleset for the default branch. GitHub refuses this until the app is
   installed on the repository.

The workflow turns the key into a token that lasts an hour and only has write access to contents.

The environment matters. A plain repository secret can be read by a workflow on any branch, and anyone with write
access can push a branch. The environment only releases the key to runs on the default branch, where a change to the
workflow has been through a pull request.

### With a deploy key

The workflow falls back to a deploy key when `DOC_SYNC_APP_CLIENT_ID` is not set. It reads the private key from the
environment secret `DOC_SYNC_DEPLOY_KEY`, and the ruleset must list deploy keys as a bypass actor.

Prefer the app. The bypass entry for deploy keys covers every deploy key of the repository, while the entry for an
app names that one app. An organisation can also turn deploy keys off.

### Without a bypass

With `push: pull-request` the action opens a pull request from `docs-sync/incoming` instead, and updates it on later
runs. It needs `contents: write` and `pull-requests: write`, and the repository setting that lets GitHub Actions
create pull requests.

Merge that pull request with a merge commit or a rebase. A squash that drops the commit messages loses the cursor.

## What the sync may push

The sync pushes whatever it replays, without review and without the checks a pull request runs. Whoever can change
the workflow on the default branch decides what the credential pushes. That is the same trust as merging to the
default branch.
