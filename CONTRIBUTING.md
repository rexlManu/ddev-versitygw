# Contributing

## Local development

Install your checkout in a test DDEV project:

```bash
ddev add-on get /path/to/ddev-versitygw
ddev restart
```

Run the image version check from the add-on repository:

```bash
./scripts/check-versitygw-image-version.sh
```

The Dockerfile and Compose file must use the same VersityGW image version. Dependabot groups image updates into one pull request.

## Tests

Run the local integration tests with Bats, `jq`, and the `bats-assert`, `bats-file`, and `bats-support` libraries installed:

```bash
bats --filter-tags '!release' tests/test.bats
```

The tests create disposable DDEV projects. They check S3 operations, HTTPS routes, bucket setup, custom credentials, private downloads, restart persistence, add-on removal, and a fresh Laravel app.

The Laravel test installs Laravel 13 through `ddev composer create-project`. Set `LARAVEL_VERSION_CONSTRAINT=^12.0` to test Laravel 12. It checks automatic adapter installation, public and signed downloads, multipart stream uploads, and browser uploads through signed URLs.

GitHub Actions tests Laravel 12 and 13 with DDEV `stable`, and Laravel 13 with DDEV `HEAD`. See [README_DEBUG.md](README_DEBUG.md) to debug a failed CI job.

## Release

1. Merge the changes into `main`.
2. Check that the GitHub Actions workflows pass.
3. Check that the repository has the `ddev-get` topic on GitHub.
4. Create a GitHub release with a semver tag.
5. Test the published release in a fresh DDEV project:

```bash
ddev add-on get rexlManu/ddev-versitygw
ddev restart
```
