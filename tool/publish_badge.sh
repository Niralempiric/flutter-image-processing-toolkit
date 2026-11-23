#!/usr/bin/env bash
# Publishes a coverage badge SVG to the `badges` branch of `origin`, creating
# the branch (with no history from the code branches) on first use.
#
#   tool/publish_badge.sh path/to/coverage.svg
#
# Meant for the end of a CI job in a disposable checkout: it switches branches
# and removes tracked files when it creates the branch.
set -euo pipefail

svg_source="${1:?usage: publish_badge.sh path/to/coverage.svg}"
branch="${BADGE_BRANCH:-badges}"
staged="$(mktemp)"
cp "$svg_source" "$staged"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  git fetch --quiet --depth=1 origin "$branch"
  git checkout --quiet -B "$branch" FETCH_HEAD
else
  git checkout --quiet --orphan "$branch"
  git rm -rfq --ignore-unmatch .
fi

cp "$staged" coverage.svg
git add coverage.svg
if git diff --cached --quiet; then
  echo "Badge unchanged."
  exit 0
fi
git commit --quiet -m "Update coverage badge"
git push --quiet origin "$branch"
echo "Badge published to $branch."
