#!/usr/bin/env bash
# Tests sync.sh against two local repositories: "mono" keeps the docs in docs/site, "docs" in content/v9.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/sync.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
failures=0

check() { # description, actual, expected
  if [ "$2" = "$3" ]; then echo "ok   $1"; else
    echo "FAIL $1"; echo "       expected: $3"; echo "       actual:   $2"; failures=$((failures + 1))
  fi
}
commit() { # repo, author, message
  git -C "$1" add -A
  GIT_AUTHOR_NAME="$2" GIT_AUTHOR_EMAIL="$2@example.com" GIT_COMMITTER_NAME="$2" GIT_COMMITTER_EMAIL="$2@example.com" \
    git -C "$1" commit -q -m "$3"
}
sync_into() { # receiving repo, then extra environment as NAME=value
  local into=$1 from this other_path local_path
  shift
  if [ "$into" = mono ]; then from=docs this=test/mono other_path=content/v9 local_path=docs/site
  else from=mono this=test/docs other_path=docs/site local_path=content/v9; fi
  (cd "$work/$into" && env THIS_REPO="$this" OTHER_REPO="test/$from" OTHER_URL="$work/$from" OTHER_BRANCH=main \
    OTHER_PATH="$other_path" LOCAL_PATH="$local_path" FETCH_FILTER="" GITHUB_OUTPUT="$work/out" "$@" "$script") >"$work/log" 2>&1
}
out() { grep "^$1=" "$work/out" | tail -1 | cut -d= -f2; }
same_trees() { [ "$(git -C "$work/mono" rev-parse HEAD:docs/site)" = "$(git -C "$work/docs" rev-parse HEAD:content/v9)" ] && echo same || echo differ; }

git init -q -b main "$work/docs"
git init -q -b main "$work/mono"
mkdir -p "$work/docs/content/v9" "$work/docs/content/other" "$work/mono/src"
printf 'one\ntwo\nthree\nfour\nfive\n' >"$work/docs/content/v9/page.nb.md"
echo other >"$work/docs/content/other/page.md"
commit "$work/docs" writer "Initial docs"
echo code >"$work/mono/src/code.txt"
commit "$work/mono" dev "Initial code"

sync_into mono && check "sync without a cursor fails" ok "error" || check "sync without a cursor fails" "$(grep -c reset-to-other "$work/log")" 1

sync_into mono MODE=reset-to-other
check "reset copies the folder" "$(same_trees)" same
check "reset records the cursor" "$(git -C "$work/mono" log -1 --format=%B | grep -c "^Synced-From: test/docs@$(git -C "$work/docs" rev-parse HEAD)$")" 1

sync_into mono
check "nothing new replays nothing" "$(out replayed)" 0

printf 'one\ntwo\nthree\nfour\nFIVE\n' >"$work/docs/content/v9/page.nb.md"
printf '\x00\x01\x02binary' >"$work/docs/content/v9/bilde æ.png"
GIT_AUTHOR_DATE="2026-01-02T03:04:05+01:00" commit "$work/docs" writer "Fix the last line (#12)"
edit=$(git -C "$work/docs" rev-parse HEAD)
echo unrelated >>"$work/docs/content/other/page.md"
commit "$work/docs" writer "Outside the folder"
sync_into mono
check "replays only commits in the folder" "$(out replayed)" 1
check "replay gives equal trees" "$(same_trees)" same
check "keeps the author and date" "$(git -C "$work/mono" log -1 --format='%an %aI')" "writer 2026-01-02T03:04:05+01:00"
check "adds the trailer" "$(git -C "$work/mono" log -1 --format='%(trailers:key=Synced-From,valueonly)' | head -1)" "test/docs@$edit"
check "points issue numbers at the other repository" "$(git -C "$work/mono" log -1 --format=%s)" "Fix the last line (test/docs#12)"
first=$(git -C "$work/mono" rev-parse HEAD)
git -C "$work/mono" reset -q --hard HEAD~1
sync_into mono
check "a repeated replay gives the same commit id" "$(git -C "$work/mono" rev-parse HEAD)" "$first"

sync_into docs MODE=reset-to-other
check "reset the other way changes nothing" "$(git -C "$work/docs" log -1 --format=%s | cut -c1-16) $(same_trees)" "docs-sync: reset same"
sync_into mono
check "does not replay its own change back" "$(out replayed)" 0

printf 'ONE\ntwo\nthree\nfour\nFIVE\n' >"$work/mono/docs/site/page.nb.md"
commit "$work/mono" dev "Edit the first line in mono"
git -C "$work/docs" mv "content/v9/bilde æ.png" "content/v9/image.png"
echo new >"$work/docs/content/v9/new.en.md"
commit "$work/docs" writer "Rename an image and add a page, see @someone and https://github.com/a/b/issues/3"
sync_into mono REFS=neutralize
sync_into docs
check "edits on both sides converge" "$(same_trees)" same
check "neutralize breaks links and mentions" "$(git -C "$work/mono" log -1 --format=%s)" "Rename an image and add a page, see @ someone and github.com/a/b/issues/3"
sync_into mono && sync_into docs
check "echoes are skipped on both sides" "$(out replayed) $(grep -c 'came from this repository' "$work/log")" "0 1"

git -C "$work/docs" checkout -q -b topic
echo a >"$work/docs/content/v9/a.md" && commit "$work/docs" writer "Topic a"
echo b >"$work/docs/content/v9/b.md" && commit "$work/docs" writer "Topic b"
git -C "$work/docs" checkout -q main
GIT_AUTHOR_NAME=m GIT_AUTHOR_EMAIL=m@example.com GIT_COMMITTER_NAME=m GIT_COMMITTER_EMAIL=m@example.com \
  git -C "$work/docs" merge -q --no-ff topic -m "Merge topic"
sync_into mono
check "a merge commit replays as one commit" "$(out replayed) $(same_trees)" "1 same"

printf 'ONE\ntwo\nthree\nfour\nmono\n' >"$work/mono/docs/site/page.nb.md"
commit "$work/mono" dev "Mono edits the last line"
printf 'ONE\ntwo\nthree\nfour\ndocs\n' >"$work/docs/content/v9/page.nb.md"
commit "$work/docs" writer "Docs edits the last line"
clash=$(git -C "$work/docs" rev-parse HEAD)
echo later >"$work/docs/content/v9/later.md"
commit "$work/docs" writer "A later commit"
before=$(git -C "$work/mono" rev-parse HEAD)
sync_into mono
check "a conflict stops the replay and names the commit" "$(out replayed) $(out conflict)" "0 $clash"
check "a conflict leaves the checkout clean" "$(git -C "$work/mono" rev-parse HEAD) $(git -C "$work/mono" status --porcelain | wc -l)" "$before 0"

sync_into docs MODE=reset-to-other
sync_into mono
check "reset-to-other resolves a conflict" "$(out replayed) $(out conflict) $(same_trees)" "0  same"

[ "$failures" -eq 0 ] && echo "All tests passed" || { echo "$failures test(s) failed"; exit 1; }
