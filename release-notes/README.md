# Release Notes

Place a file named `<version>.md` here before running `make release`.

CI will combine it with the auto-generated git-cliff changelog section
and post the result as the Gitea release body.

Example: `release-notes/v0.2.0.md`

---

## Template

```markdown
## Highlights

One or two sentences on what this release is about and why it matters.

## Upgrade notes

Any action required from operators when upgrading from the previous version.

## Known issues

Anything the user should be aware of that is not yet fixed.
```

If no file exists for the current version, the Gitea release body will contain
only the auto-generated changelog section.
