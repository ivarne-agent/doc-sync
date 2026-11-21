#!/usr/bin/env bash
# Replays commits that touch a folder in another repository onto the current checkout.
# See README.md for the model. Run from the root of the receiving repository.
set -euo pipefail

: "${OTHER_REPO:?owner/name of the repository to sync from}"
: "${OTHER_BRANCH:?branch in the other repository}"
: "${OTHER_PATH:?folder in the other repository}"
: "${LOCAL_PATH:?folder in this repository}"
THIS_REPO="${THIS_REPO:-${GITHUB_REPOSITORY:?set THIS_REPO to owner/name of this repository}}"
MODE="${MODE:-sync}"                 # sync | reset-to-other
OTHER_REF="${OTHER_REF:-}"           # reset-to-other only: commit to reset to, default the branch tip
REFS="${REFS:-qualify}"              # qualify | neutralize | keep
OTHER_URL="${OTHER_URL:-https://github.com/${OTHER_REPO}.git}"
FETCH_FILTER="${FETCH_FILTER-blob:none}"
OTHER_PATH="${OTHER_PATH%/}"
LOCAL_PATH="${LOCAL_PATH%/}"
REMOTE=docs-sync-other

# A fixed committer and the source commit's dates make a replay produce the same commit ids on every run,
# so an unchanged pull request branch is not pushed again.
export GIT_COMMITTER_NAME="docs-sync"
export GIT_COMMITTER_EMAIL="docs-sync@users.noreply.github.com"

die() { echo "docs-sync: $*" >&2; exit 1; }
output() { if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "$1=$2" >>"$GITHUB_OUTPUT"; fi; }

# A bare "#12" would point at issue 12 in this repository once the message lands here.
#   qualify:    make it point back at the other repository
#   neutralize: stop GitHub from linking or notifying anyone, for trials against a repository we do not own
rewrite_refs() {
  case "$REFS" in
    qualify) sed -E "s~(^|[^[:alnum:]_/])#([0-9]+)~\1${OTHER_REPO}#\2~g" ;;
    neutralize)
      sed -E -e 's~#([0-9]+)~no. \1~g' \
        -e 's~https?://(www\.)?github\.com/~github.com/~g' \
        -e 's~(^|[^[:alnum:]_.+-])@([[:alnum:]])~\1@ \2~g'
      ;;
    keep) cat ;;
    *) die "unknown REFS '$REFS'" ;;
  esac
}

[ -z "$(git status --porcelain)" ] || die "the working tree is not clean"
base=$(git rev-parse HEAD)
output base "$base"

git remote remove "$REMOTE" 2>/dev/null || true
git remote add "$REMOTE" "$OTHER_URL"
filter=()
if [ -n "$FETCH_FILTER" ]; then
  # Blobs are fetched on demand, so only the files a replayed commit touches are downloaded.
  git config "remote.$REMOTE.promisor" true
  git config "remote.$REMOTE.partialclonefilter" "$FETCH_FILTER"
  filter=(--filter="$FETCH_FILTER")
fi
git fetch --quiet --no-tags "${filter[@]}" "$REMOTE" "+refs/heads/$OTHER_BRANCH:refs/remotes/$REMOTE/$OTHER_BRANCH"
tip=$(git rev-parse "refs/remotes/$REMOTE/$OTHER_BRANCH")
output tip "$tip"

if [ "$MODE" = "reset-to-other" ]; then
  sha=$(git rev-parse --verify --quiet "${OTHER_REF:-$tip}^{commit}") || die "unknown commit '$OTHER_REF'"
  # No grep -q: it would close the pipe early and fail the pipeline.
  [ -n "$(git rev-list --first-parent "$tip" | grep -x "$sha" || true)" ] || die "$sha is not on the first-parent history of $OTHER_BRANCH"
  git rm -r --quiet --ignore-unmatch -- "$LOCAL_PATH"
  git clean -fdq -- "$LOCAL_PATH"
  git read-tree -u --prefix="$LOCAL_PATH/" "$sha:$OTHER_PATH"
  GIT_COMMITTER_DATE=$(git log -1 --format=%cI "$sha") GIT_AUTHOR_DATE=$(git log -1 --format=%cI "$sha") \
    GIT_AUTHOR_NAME="$GIT_COMMITTER_NAME" GIT_AUTHOR_EMAIL="$GIT_COMMITTER_EMAIL" \
    git commit --quiet --allow-empty -m "docs-sync: reset $LOCAL_PATH to $OTHER_REPO@${sha:0:10}" -m "Synced-From: $OTHER_REPO@$sha
Synced-Reset: $OTHER_REPO@$sha"
  echo "Reset $LOCAL_PATH to $OTHER_REPO@$sha"
  output replayed 0
  output conflict ""
  exit 0
fi
[ "$MODE" = "sync" ] || die "unknown MODE '$MODE'"

# The cursor is the newest commit of the other repository that a Synced-From line in our history names.
# Searching whole messages, not only trailers, also finds the lines when a merge has folded messages together.
seen=$(git log --format=%B HEAD | grep -oE "Synced-From: ${OTHER_REPO//./\\.}@[0-9a-f]{40}" | sed 's/.*@//' | sort -u || true)
[ -n "$seen" ] || die "no 'Synced-From: $OTHER_REPO@<sha>' in the history. Run once with mode reset-to-other"
cursor=$(git rev-list --first-parent "$tip" | grep -m1 -Fx -f <(printf '%s\n' "$seen") || true)
[ -n "$cursor" ] || die "none of the synced commits is on the first-parent history of $OTHER_BRANCH"
output cursor "$cursor"

# When the other repository has reset its folder to ours, its earlier commits were overwritten there,
# so they must not be replayed here. That is how a reset on one side resolves a conflict on both.
start=$(git log --first-parent -1 --format=%H --grep="^Synced-Reset: ${THIS_REPO//./\\.}@" "$cursor..$tip")
start=${start:-$cursor}

replayed=0
conflict=""
patch=$(mktemp)
trap 'rm -f "$patch"' EXIT
for c in $(git rev-list --reverse --first-parent "$start..$tip" -- "$OTHER_PATH"); do
  msg=$(git log -1 --format=%B "$c")
  if grep -qE "^Synced-From: ${THIS_REPO//./\\.}@" <<<"$msg"; then
    echo "skip   ${c:0:10} (came from this repository)"
    continue
  fi
  parent=$(git rev-parse --verify --quiet "$c^1" || git hash-object -t tree /dev/null)
  git diff --binary --full-index --relative="$OTHER_PATH/" "$parent" "$c" -- "$OTHER_PATH" >"$patch"
  [ -s "$patch" ] || continue
  if ! git apply --3way --whitespace=nowarn --directory="$LOCAL_PATH" "$patch"; then
    git reset --quiet --hard
    git clean -fdq -- "$LOCAL_PATH"
    conflict=$c
    echo "stop   ${c:0:10} does not apply: $(git log -1 --format=%s "$c")"
    break
  fi
  if git diff --cached --quiet; then
    echo "skip   ${c:0:10} (already present)"
    continue
  fi
  printf '%s\n' "$msg" | rewrite_refs | git interpret-trailers --trailer "Synced-From: $OTHER_REPO@$c" |
    GIT_AUTHOR_NAME=$(git log -1 --format=%an "$c") GIT_AUTHOR_EMAIL=$(git log -1 --format=%ae "$c") \
      GIT_AUTHOR_DATE=$(git log -1 --format=%aI "$c") GIT_COMMITTER_DATE=$(git log -1 --format=%cI "$c") \
      git commit --quiet --cleanup=whitespace -F -
  replayed=$((replayed + 1))
  echo "replay ${c:0:10} $(git log -1 --format=%s "$c")"
done

echo "Replayed $replayed commit(s) from $OTHER_REPO since ${cursor:0:10}"
output replayed "$replayed"
output conflict "$conflict"
