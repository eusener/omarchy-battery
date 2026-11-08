#!/usr/bin/env bash
# Publish the prepared repository and open the initial implementation PR.
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
case "${1:-}" in
  --public|--private) visibility=$1 ;;
  *) echo 'Usage: bash scripts/publish-gh.sh --public|--private' >&2; exit 2 ;;
esac
repo=eusener/omarchy-battery
if [[ -n $(git status --porcelain) ]]; then
  echo 'Commit or save local changes before publishing.' >&2
  exit 1
fi
gh auth status
bash scripts/check.sh
# If a prior attempt already created the repository, do not recreate it.
if ! gh repo view "$repo" --json name >/dev/null 2>&1; then
  gh repo create "$repo" "$visibility" --description 'Omarchy Shell battery identity, capacity, health and power panel'
fi
remote_url=$(git remote get-url origin 2>/dev/null || true)
case "$remote_url" in
  '') git remote add origin "https://github.com/$repo.git" ;;
  "https://github.com/$repo.git"|"https://github.com/$repo"|"git@github.com:$repo.git") ;;
  *) echo 'origin points to another repository; inspect it before publishing.' >&2; exit 1 ;;
esac
git push -u origin main
git push -u origin feat/battery-details
existing_pr=$(gh pr list --repo "$repo" --head feat/battery-details --base main --state open --json url --jq '.[0].url // empty')
if [[ -n $existing_pr ]]; then
  printf '%s\n' "$existing_pr"
else
  gh pr create --repo "$repo" --base main --head feat/battery-details \
    --title 'feat: add installable battery health and identity panel' \
    --body-file docs/PR.md
fi
