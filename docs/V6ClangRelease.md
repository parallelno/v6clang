# V6CLANG Release Procedure

Releases are produced by `.github/workflows/release.yml`, which is
triggered by pushing an annotated tag matching `v*` (or via the
**Run workflow** button on the Actions page). The job builds clang +
llc + lld + llvm-objcopy on `windows-latest`, packages the
`dist/v6clang-<version>-windows-x64/` tree, and attaches the `.zip` to a
GitHub Release named after the tag.

## Naming Convention

Tags follow `vYYYY.MM.DD` (UTC date of the cut). Patch suffixes
(`-1`, `-2`) are allowed if the same day produces multiple drops.

## Cutting a Release

`scripts/publish.ps1` automates the full procedure (clean-check, build,
package, tag, push):

```powershell
# Interactive: opens your git editor for the tag message
pwsh scripts\publish.ps1

# Scripted: pass highlights directly
pwsh scripts\publish.ps1 -Highlights "Fix sieve regression","Update docs"

# Dry run: creates the tag locally without pushing
pwsh scripts\publish.ps1 -Highlights "Fix X" -DryRun

# Skip the build step (already known-good)
pwsh scripts\publish.ps1 -SkipBuild -Highlights "Fix X"
```

`-Version` overrides the auto-derived UTC date tag (e.g.
`-Version v2026.05.27-1` for a same-day patch drop).

## Verifying the Workflow

```powershell
# Watch the run on GitHub Actions:
Start-Process "https://github.com/parallelno/v6clang/actions"
```

The workflow finishes by creating a draft Release. Edit it on GitHub to
flesh out the release notes if needed, then publish.

## Rolling Back a Bad Tag

If the workflow fails or the tag was created in error:

```powershell
# Delete locally and on origin (also deletes the workflow's draft release
# manually via the Releases page if one was created).
git tag -d v2026.04.29
git push origin :refs/tags/v2026.04.29
```

Avoid re-using the same tag name after a publish — bump to the next
patch suffix (e.g. `v2026.04.29-1`) instead.

## Workflow Inputs

`workflow_dispatch` accepts an optional `version` input that overrides
the auto-derived UTC date. Use it for off-cycle drops without creating
a git tag (the workflow will still tag/release internally using the
override).
