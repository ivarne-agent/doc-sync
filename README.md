# doc-sync

A trial of keeping the Altinn Studio v9 docs in two repositories at once, so that the team can write them in the
altinn-studio monorepo while [altinn-studio-docs](https://github.com/Altinn/altinn-studio-docs) keeps publishing them.

This repository stands in for the monorepo. `docs/site` here mirrors `content/altinn-studio/v9` in the docs
repository. A [workflow](.github/workflows/docs-sync.yaml) runs once a day and replays new commits from the docs
repository onto `main`.

Only that direction runs here, since the trial must not write to the docs repository. The
[tests](.github/actions/docs-sync/sync.test.sh) cover both directions with two local repositories.

## Where things are

- [The docs-sync action](.github/actions/docs-sync/action.yml) is what a repository calls. It runs
  [sync.sh](.github/actions/docs-sync/sync.sh) and then pushes the result.
- [docs/](docs/README.md) explains how the sync works, how to set it up, how to operate it, and what remains before
  it can run between the real repositories.
- `docs/site` is the synced content. Do not read it as documentation of this repository.

## Running it locally

```sh
.github/actions/docs-sync/sync.test.sh
```

To replay onto a local checkout without pushing anything:

```sh
THIS_REPO=ivarne-agent/doc-sync OTHER_REPO=Altinn/altinn-studio-docs OTHER_BRANCH=master \
  OTHER_PATH=content/altinn-studio/v9 LOCAL_PATH=docs/site REFS=neutralize .github/actions/docs-sync/sync.sh
```
