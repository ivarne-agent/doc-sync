# Moving to the real repositories

What the trial has shown, and what is left before the sync can run between altinn-studio and altinn-studio-docs.
Written on 22 November 2026.

## What the trial has shown

- The sync replays real commits from the docs repository with their authors, dates and messages. After a replay the
  two folders have the same tree hash.
- A run with nothing new replays nothing and pushes nothing.
- A GitHub App on the ruleset's bypass list pushes replayed commits to a branch that otherwise only takes
  squash-merged pull requests. A deploy key does too.
- An environment limited to the default branch keeps the credential from a workflow on another branch.
- The pull request route works when the pull request is merged with a merge commit.

## What the trial has not shown

- **A run started by the timer.** Every run so far was started by hand. The half-hourly schedule that the repository
  started with never fired in the 70 minutes it was watched. Check the workflow's runs for one with the event
  `schedule`.
- **The direction into the docs repository.** Only the tests cover it.
- **A real conflict.** Only the tests cover conflicts and resets across two sides.
- **A commit that arrives on its own.** The docs repository has had no new v9 commit since the trial started.

## Decisions to make

- **Where the folder goes in the monorepo.** `docs/site` is a placeholder.
- **Whether `content/altinn-studio/shared/studioctl` moves too.** The action syncs one folder. A second folder needs
  a second call, with its own cursor.
- **Who resolves a conflict**, and how they hear about it. Today the only signal is a failed workflow run.
- **How often it runs.** The timer sets how long a merged change takes to reach the site.
- **Whether an unreviewed push to `main` is acceptable.** A change made in the docs repository reaches the monorepo
  without the monorepo's review or checks.

## Work to do

- Create one GitHub App for each repository, or one app installed on both. Someone with admin rights in the Altinn
  organisation must add it to the bypass list on monorepo `main` and on the docs repository's `master`.
- Put the action in the monorepo. The docs repository calls it by a pinned commit, and Renovate can update the pin.
- Use `refs: qualify`, so that issue numbers in replayed messages point back at the repository they came from.
- Add a scheduled job that compares the two tree hashes and reports a difference.
- Do the first reset on one side only, at a moment when nobody is merging docs changes.
- Tell the people who write the docs that both folders are now writable, and what a failed sync run means.
