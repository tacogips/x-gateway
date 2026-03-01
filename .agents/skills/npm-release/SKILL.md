---
name: npm-release
description: Publish x-gateway to npm with Bun, including secure token handling, dry-run checks, and post-publish verification.
allowed-tools: Bash, Read, Write, Grep, Glob
user-invocable: true
argument-hint: [publish|dry-run]
---

# npm Release Skill

Use this skill to publish `x-gateway` package versions to npm.

## Preconditions

1. Build and tests pass:
```bash
task ci
```
2. Dist artifacts exist:
```bash
bun run build
```
3. Version is correct and not already published:
```bash
VERSION=$(bun -e "const p = await Bun.file('./package.json').json(); console.log(p.version)")
bun -e "const version=process.env.VERSION; const r=await fetch('https://registry.npmjs.org/x-gateway'); if(!r.ok){throw new Error('registry query failed')} const body=await r.json(); const versions=Object.keys(body.versions ?? {}); if(versions.includes(version)){process.exit(1)}"
```
4. Auth is valid (`NPM_TOKEN` recommended):
```bash
test -n "$NPM_TOKEN"
```

## Auth Standard

Prefer ephemeral npm config from environment token:

```bash
TMP_NPMRC=$(mktemp)
cat > "$TMP_NPMRC" <<'EONPMRC'
//registry.npmjs.org/:_authToken=${NPM_TOKEN}
EONPMRC
```

Use publish commands with:
```bash
NPM_CONFIG_USERCONFIG="$TMP_NPMRC" <publish command>
```

Cleanup:
```bash
rm -f "$TMP_NPMRC"
```

Do not commit tokens or write plaintext tokens into repository files.

## Publish Commands

Dry run:
```bash
NPM_CONFIG_USERCONFIG="$TMP_NPMRC" bunx npm publish --access public --dry-run
```

Real publish:
```bash
NPM_CONFIG_USERCONFIG="$TMP_NPMRC" bunx npm publish --access public
```

## Verification

1. Confirm published version:
```bash
npm view x-gateway version
```
2. Verify registry metadata:
```bash
curl -s https://registry.npmjs.org/x-gateway/latest
```
3. Confirm package installability:
```bash
bunx npm view x-gateway@"$VERSION" name version
```

## Failure Handling

1. If publish returns version exists (`403`/`EPUBLISHCONFLICT`), stop and request version bump.
2. If publish fails with `EOTP`, use automation token or provide `--otp <code>`.
3. If publish fails after upload uncertainty, verify on registry before retrying to avoid duplicate attempts.
4. If dry-run output includes unexpected files, stop and fix `files`/build outputs before publishing.

## Security Notes

Follow `.agents/skills/supply-chain-secure-publish/SKILL.md` for hardening checks before final publish.
