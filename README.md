# doc-sync

A trial of syncing the Altinn Studio v9 docs between two repositories. This repository stands in for the
altinn-studio monorepo. `docs/site` here mirrors `content/altinn-studio/v9` in
[altinn-studio-docs](https://github.com/Altinn/altinn-studio-docs).

Only one direction runs in the trial, from the docs repository to this one, since the trial must not write to the docs
repository. The [tests](.github/actions/docs-sync/sync.test.sh) cover both directions with two local repositories.

## How it works

The [workflow](.github/workflows/docs-sync.yaml) runs on a timer and calls the
[docs-sync action](.github/actions/docs-sync/action.yml), which runs [sync.sh](.github/actions/docs-sync/sync.sh).

- Each replayed commit ends with `Synced-From: <repository>@<sha>`, naming the commit it came from.
- The cursor is the newest commit of the other repository that our history names in such a line.
- The sync replays the other repository's commits after the cursor that touch the folder, one commit each, with a
  three-way merge. It keeps the author, the date and the message.
- It skips a commit that carries `Synced-From` for this repository, since that change started here.
- It pushes the replayed commits straight to `main`. A repeated run produces the same commit ids.

## How the sync gets past the branch rules

`main` only takes squash-merged pull requests, like a repository where a squash would drop the `Synced-From` lines.
The sync pushes with a deploy key instead:

- The key has write access to this repository only, and the ruleset for `main` lists deploy keys as a bypass actor.
- The private key is a secret of the `docs-sync` environment, which only releases it to workflow runs on `main`. A
  workflow on another branch cannot read it.
- Without the key, the action can open a pull request instead (`push: pull-request`). That pull request must then be
  merged with a merge commit or a rebase.

## When a commit does not apply

The sync stops at the first commit that conflicts. It still pushes the commits before it, and the workflow run fails
and names the commit. Two ways out:

- Make the change by hand in a pull request, and end the commit message with the `Synced-From` line for that commit.
- Run the workflow with mode `reset-to-other`. It makes the folder identical to the other repository's, and records
  that in a `Synced-Reset` line. The other side then skips its own commits from before the reset.

## Running it locally

```sh
.github/actions/docs-sync/sync.test.sh

THIS_REPO=ivarne-agent/doc-sync OTHER_REPO=Altinn/altinn-studio-docs OTHER_BRANCH=master \
  OTHER_PATH=content/altinn-studio/v9 LOCAL_PATH=docs/site REFS=neutralize .github/actions/docs-sync/sync.sh
```
