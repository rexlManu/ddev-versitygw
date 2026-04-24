# How to debug tests (GitHub Actions)

Repository: `rexlManu/ddev-versitygw`

1. Register an SSH key with GitHub.
2. Add the matching key to `~/.ssh/config` for `*.tmate.io`.
3. Open the repository Actions page and run the `tests` workflow with `Debug with tmate`.
4. Wait for the job to print the `ssh ...@tmate.io` command.
5. SSH in and run:

```bash
bats ./tests/test.bats
```

This follows the normal DDEV add-on template debug flow.
