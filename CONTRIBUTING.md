# Contributing

## Local Development

Work on the add-on from the repository root and test it against a throwaway DDEV project:

```bash
ddev add-on get /path/to/ddev-versitygw
ddev restart
```

Useful checks:

- `ddev describe`
- `ddev logs -s versitygw`
- upload an object through the provisioned S3 bucket
- fetch the object from `AWS_URL/<key>`

## CI

The repository uses `.github/workflows/tests.yml` with the DDEV add-on test action against `stable` and `HEAD`.

If you need to debug CI interactively, follow the instructions in `README_DEBUG.md`.

## Release Process

1. Merge the desired state into `main`.
2. Confirm the GitHub Actions `tests` workflow passes.
3. Confirm the repository has the `ddev-get` topic on GitHub.
4. Create a GitHub release with a semver tag.
5. Verify install from GitHub:

```bash
ddev add-on get rexlManu/ddev-versitygw
ddev restart
```
