# How the sync works

Two repositories each hold a copy of the same folder. Each repository runs the sync on a timer. A run reads the other
repository and writes only to its own, so no credential ever crosses between the two. Both repositories are public,
so reading needs no credential at all.

[sync.sh](../.github/actions/docs-sync/sync.sh) does the work. It replays commits. It does not copy the folder, since
a copy would overwrite whatever changed on the receiving side since the last run.

## The cursor

Each replayed commit ends with a line that names the commit it came from:

```
Synced-From: Altinn/altinn-studio-docs@358fa9154c31fc5b26e3890a6b20173609e7b070
```

The cursor is the newest commit of the other repository that our history names in such a line. Nothing else stores
state. A run that finds nothing new commits nothing, and the next run looks at the same range again.

The sync searches whole commit messages for the line, not only the trailer block. A squash merge that keeps the
messages of its commits therefore keeps the cursor. A squash merge that drops them loses it.

## What a run does

1. Fetch the other repository's branch. Blobs come on demand, so only the files that a replayed commit touches are
   downloaded.
2. Find the cursor.
3. List the other repository's commits after the cursor that touch the folder, along first parents.
4. Skip each commit that carries `Synced-From` for this repository. That change started here.
5. Apply each remaining commit's change to the folder with a three-way merge, and commit it with the same author,
   date and message, plus the `Synced-From` line.
6. Stop at the first commit that does not apply.

The [action](../.github/actions/docs-sync/action.yml) then pushes the commits to the branch, or opens a pull request
with them.

## Properties to rely on

- **Changes on both sides converge.** When both repositories change different lines between two runs, each replays
  the other's commit. The histories differ in order, and the folders end up identical.
- **A repeated run gives the same commit ids.** The committer is fixed and the dates come from the source commit. An
  unmerged pull request branch is therefore not pushed again.
- **Authors and dates survive**, so a site that shows "last modified" from Git keeps showing the right date.
- **A merge commit becomes one commit.** The sync follows first parents, so a merged branch arrives as one commit
  with the merge commit's author.

## References in commit messages

A bare `#12` in a replayed message would point at issue 12 in the receiving repository. The `refs` input decides
what happens to it:

- `qualify` rewrites it to `owner/name#12`, so that it points back at the repository it came from. This is the
  default, and what the real repositories should use.
- `neutralize` breaks issue references, GitHub URLs and @-mentions. This trial uses it, so that its commits do not
  add backlinks to real pull requests or notify the people named in them.
- `keep` leaves the message alone.

## Reset

The mode `reset-to-other` makes the folder identical to the other repository's at one commit. Its commit carries
both a `Synced-From` and a `Synced-Reset` line.

- On the side that resets, the cursor starts over from the reset. A reset to an older commit moves the cursor back.
- On the other side, the sync skips its own commits from before the reset, since the reset overwrote them. That is
  how a reset on one side resolves a conflict on both.

A repository needs one reset before its first sync, to get a cursor.

## Limits

- **Conflicting changes need a person.** When both sides change the same lines between two runs, both stop. See
  [Operating](operating.md#when-a-commit-does-not-apply).
- **A reset can race with a replay.** If one side replays a commit while the other side resets past it, the folders
  drift apart without a conflict. The [equality check](operating.md#checking-that-the-folders-are-equal) finds it.
- **The commits arrive late.** The timer decides how late. GitHub also starts scheduled workflows late when it is
  busy.
