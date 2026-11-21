# Operating

## Checking that the folders are equal

Git gives two folders with the same content the same tree hash, whatever their history. Compare them:

```sh
gh api "repos/Altinn/altinn-studio-docs/contents/content/altinn-studio?ref=master" -q '.[] | select(.name=="v9") | .sha'
gh api "repos/ivarne-agent/doc-sync/contents/docs?ref=main" -q '.[] | select(.name=="site") | .sha'
```

The hashes differ while one side has commits that the other has not replayed yet. If they still differ after a run
that replayed nothing, the folders have drifted. Find the difference, and fix it with a commit or with a
[reset](#resetting).

## Reading a run

The Sync step prints one line for each commit it looks at:

- `replay` for a commit it applied
- `skip` for a commit that came from this repository, or whose change is already present
- `stop` for a commit that does not apply

It ends with the number of commits it replayed and the cursor it started from.

## When a commit does not apply

The sync stops at the first commit that conflicts. It still pushes the commits before it. The run fails and names the
commit. Every later run stops at the same commit until someone resolves it. When both sides changed the same lines,
both sides are stuck.

Two ways out:

- **Resolve it by hand.** Make the change in this repository, and end the commit message with the `Synced-From` line
  for the commit that did not apply. The next run starts after it. When the change goes through a squash-merged pull
  request, check that the line is still in the squash commit's message.
- **Reset.** Decide which side is right, and reset the other side to it.

A resolution by hand carries a `Synced-From` line, so the other side skips it. If the other side is stuck on the same
conflict, it stays stuck. Reset that side.

## Resetting

Run the workflow by hand with mode `reset-to-other`. It makes the folder identical to the other repository's, at the
tip of its branch or at the commit given in `other-ref`.

A reset discards every change in the folder that the other side does not have. Let the other side replay what it is
missing first, or accept the loss.

## Changing how often it runs

The timer is the `cron` line in the [workflow](../.github/workflows/docs-sync.yaml). A manual run does the same as a
scheduled one.
