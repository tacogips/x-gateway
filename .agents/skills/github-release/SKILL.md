---
name: github-release
description: Publish x-gateway artifacts to GitHub Releases using gh CLI with tag/version validation and idempotent retry behavior.
allowed-tools: Bash, Read, Write, Grep, Glob
user-invocable: true
argument-hint: [version or tag]
---

# GitHub Release Skill

Use this skill to create or update GitHub Releases for x-gateway.

## Preconditions

1. GitHub auth is valid:
```bash
gh auth status
```
2. Working tree is clean for release operations:
```bash
git status --short
```
3. Version is resolved from `VERSION` unless user explicitly sets tag:
```bash
VERSION=$(tr -d '[:space:]' < VERSION)
TAG="v${VERSION}"
```

## Required Artifacts

Expected assets for release upload:
- `dist/homebrew/x-gateway-<version>-darwin-arm64.tar.gz`
- `dist/homebrew/x-gateway-<version>-darwin-x64.tar.gz`
- `dist/homebrew/x-gateway-<version>-darwin-arm64.tar.gz.sha256`
- `dist/homebrew/x-gateway-<version>-darwin-x64.tar.gz.sha256`

If artifacts are missing, invoke `binary-release` first.

## Standard Commands

1. Ensure tag exists (create if missing):
```bash
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists"
else
  git tag -a "$TAG" -m "Release $TAG"
  git push origin "$TAG"
fi
```

2. Create GitHub release when absent:
```bash
gh release view "$TAG" >/dev/null 2>&1 || \
  gh release create "$TAG" \
    --title "x-gateway $TAG" \
    --generate-notes
```

3. Upload or overwrite assets:
```bash
gh release upload "$TAG" dist/homebrew/x-gateway-"$VERSION"-darwin-*.tar.gz* --clobber
```

## Verification

1. Confirm release page:
```bash
gh release view "$TAG" --json url --jq '.url'
```
2. Confirm tag target commit:
```bash
git rev-list -n 1 "$TAG"
```
3. Confirm all required asset names are present:
```bash
gh release view "$TAG" --json assets --jq '.assets[].name'
```

## Failure Handling

1. If `gh release create` fails due to existing release, switch to upload-only mode.
2. If tag points to wrong commit, stop and ask whether retagging is authorized.
3. If partial upload fails, re-run `gh release upload ... --clobber` for missing files.
