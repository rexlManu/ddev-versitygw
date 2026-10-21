#!/usr/bin/env bats

setup() {
  set -eu -o pipefail

  export GITHUB_REPO=rexlManu/ddev-versitygw
  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH:-}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  mkdir -p "${HOME}/tmp"
  TESTDIR="$(mktemp -d "${HOME}/tmp/ddev-versitygw-test.XXXXXX")"
  PROJNAME="$(basename "${TESTDIR}" | tr '[:upper:].' '[:lower:]-')"
  export DIR TESTDIR PROJNAME
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true
  cd "${TESTDIR}"
  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site --php-version=8.4
  assert_success
  run ddev start -y
  assert_success
}

teardown() {
  set -eu -o pipefail
  if [[ "${BATS_TEST_COMPLETED:-}" != 1 ]]; then
    ddev logs -s versitygw >&3 2>&1 || true
  fi
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1
  # Removing the add-on first leaves its volumes outside DDEV's project config.
  docker volume rm "ddev-${PROJNAME}_versitygw-s3" "ddev-${PROJNAME}_versitygw-versioning" "ddev-${PROJNAME}_versitygw-iam" >/dev/null 2>&1 || true
  rm -rf "${TESTDIR:?}"
}

install_local() {
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  refute_output --partial 'Task failed'
}

# Use the local router even when the host cannot resolve *.ddev.site.
curl() {
  command curl \
    --resolve "${PROJNAME}.ddev.site:17070:127.0.0.1" \
    --resolve "${PROJNAME}.ddev.site:17071:127.0.0.1" \
    --resolve "${PROJNAME}.ddev.site:17080:127.0.0.1" "$@"
}

health_checks() {
  run ddev exec -s versitygw versitygw --version
  assert_success
  assert_output --partial "Version"

  run ddev versitygw-aws s3api list-buckets
  assert_success
  assert_output --partial '"Name": "local"'

  run ddev versitygw-aws s3api get-bucket-policy --bucket local
  assert_success
  assert_output --partial "PublicRead"

  run ddev exec -s versitygw sh -c 'printf hello > /tmp/test.txt'
  assert_success
  run ddev versitygw-aws s3 cp /tmp/test.txt s3://local/test.txt
  assert_success

  run curl -fsS "https://${PROJNAME}.ddev.site:17080"
  assert_success
  assert_output --partial "https://${PROJNAME}.ddev.site:17070"
  assert_output --partial "https://${PROJNAME}.ddev.site:17071"
  refute_output --partial "http://${PROJNAME}.ddev.site:17070"

  run curl -fsS "https://${PROJNAME}.ddev.site:17070/health"
  assert_success

  # A real admin response must reject anonymous access.
  run curl -sS -o /dev/null -w '%{http_code}' -X PATCH "https://${PROJNAME}.ddev.site:17071/list-users"
  assert_success
  assert_output "403"

  run curl -fsS "https://${PROJNAME}.ddev.site:17070/local/test.txt"
  assert_success
  assert_output "hello"

  run ddev describe -j
  assert_success
  assert_output --partial '"short_name":"versitygw"'
  assert_output --partial "https://${PROJNAME}.ddev.site:17080"
  assert_output --partial "Default bucket: local"
}

@test "install, restart, and remove from a generic project" {
  install_local
  health_checks

  run ddev restart -y
  assert_success
  refute_output --partial 'Task failed'
  run curl -fsS "https://${PROJNAME}.ddev.site:17070/local/test.txt"
  assert_success
  assert_output "hello"

  run ddev add-on remove versitygw
  assert_success
  assert_file_not_exists .ddev/config.versitygw.yaml
  assert_file_not_exists .ddev/docker-compose.versitygw.yaml
  assert_file_not_exists .ddev/commands/host/versitygw
  assert_file_not_exists .ddev/commands/versitygw/versitygw-aws
  run ddev restart -y
  assert_success
  # shellcheck disable=SC2016 # Expand variables inside the web container.
  run ddev exec sh -c 'test -z "${AWS_ENDPOINT:-}"'
  assert_success
}

@test "custom credentials, region, bucket, and private policy" {
  run ddev dotenv set .ddev/.env.versitygw --versitygw-access-key=test-access --versitygw-secret-key=test-secret-123 --versitygw-region=eu-central-1 --versitygw-default-bucket=assets
  assert_success
  install_local

  run ddev versitygw-aws s3api head-bucket --bucket assets
  assert_success
  run ddev exec -s versitygw sh -c 'printf private > /tmp/private.txt'
  assert_success
  run ddev versitygw-aws s3 cp /tmp/private.txt s3://assets/private.txt
  assert_success
  run curl -fsS "https://${PROJNAME}.ddev.site:17070/assets/private.txt"
  assert_success
  assert_output "private"

  run ddev dotenv set .ddev/.env.versitygw --versitygw-public-read=false
  assert_success
  run ddev restart -y
  assert_success
  run curl -sS -o /dev/null -w '%{http_code}' "https://${PROJNAME}.ddev.site:17070/assets/private.txt"
  assert_success
  assert_output "403"
  run ddev versitygw-aws s3api head-object --bucket assets --key private.txt
  assert_success

  # Deleting an already absent policy must remain safe on later starts.
  run ddev restart -y
  assert_success
  # shellcheck disable=SC2016 # Expand variables inside the web container.
  run ddev exec sh -c 'test "$AWS_ACCESS_KEY_ID" = test-access && test "$AWS_BUCKET" = assets && test "$AWS_DEFAULT_REGION" = eu-central-1'
  assert_success
}

@test "Laravel configures S3 automatically and supports public and signed URLs" {
  run ddev config --project-type=laravel --composer-root=app --docroot=app/public
  assert_success
  run ddev restart -y
  assert_success
  run ddev composer create-project laravel/laravel . "${LARAVEL_VERSION_CONSTRAINT:-^13.0}" --no-interaction --prefer-dist
  assert_success
  cp app/.env env-before
  run ddev artisan config:cache
  assert_success
  install_local
  assert_file_not_exists app/bootstrap/cache/config.php
  run cmp env-before app/.env
  assert_success

  cp "${DIR}/tests/laravel.php" .ddev/versitygw-test.php
  run ddev exec php /mnt/ddev_config/versitygw-test.php
  assert_success
  urls="${output}"
  run ddev exec env -u VERSITYGW_RETAIN_VISIBILITY php /mnt/ddev_config/versitygw-test.php production-default
  assert_success
  assert_output 'Production default passed.'
  public_url="$(jq -er .public_url <<<"${urls}")"
  temporary_url="$(jq -er .temporary_url <<<"${urls}")"
  upload_url="$(jq -er .upload_url <<<"${urls}")"

  run curl -fsS "${public_url}"
  assert_success
  assert_output 'Hello from Laravel'
  run curl -fsS "${temporary_url}"
  assert_success
  assert_output 'Hello from Laravel'

  run curl -fsS -D - -o /dev/null -X OPTIONS -H "Origin: https://${PROJNAME}.ddev.site" -H 'Access-Control-Request-Method: PUT' -H 'Access-Control-Request-Headers: content-type' "${upload_url}"
  assert_success
  assert_output --regexp '[Aa]ccess-[Cc]ontrol-[Aa]llow-[Oo]rigin: \*'

  upload_headers=()
  while IFS= read -r header; do
    upload_headers+=(-H "${header}")
  done < <(jq -r '.upload_headers | to_entries[] | "\(.key): \(.value | join(", "))"' <<<"${urls}")
  run curl -fsS -X PUT "${upload_headers[@]}" --data-binary 'Browser upload' "${upload_url}"
  assert_success
  run ddev exec php /mnt/ddev_config/versitygw-test.php verify-upload
  assert_success
  assert_output 'Signed upload passed.'

  cp app/config/filesystems.php filesystems-before.php
  cp app/composer.json composer-before.json
  cp app/composer.lock composer-before.lock
  run ddev dotenv set .ddev/.env.versitygw --versitygw-public-read=false
  assert_success
  run ddev restart -y
  assert_success
  refute_output --partial 'Task failed'
  refute_output --partial 'installing the Laravel S3 adapter'
  run cmp filesystems-before.php app/config/filesystems.php
  assert_success
  run cmp composer-before.json app/composer.json
  assert_success
  run cmp composer-before.lock app/composer.lock
  assert_success
  run curl -sS -o /dev/null -w '%{http_code}' "${public_url}"
  assert_success
  assert_output '403'
  run curl -fsS "${temporary_url}"
  assert_success
  assert_output 'Hello from Laravel'
}

# bats test_tags=release
@test "install from release" {
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success
  run ddev exec -s versitygw versitygw --version
  assert_success
  run curl -fsS "https://${PROJNAME}.ddev.site:17080"
  assert_success
  run ddev exec -s versitygw sh -c 'AWS_ACCESS_KEY_ID=versity AWS_SECRET_ACCESS_KEY=versitysecret AWS_DEFAULT_REGION=us-east-1 AWS_EC2_METADATA_DISABLED=true aws --endpoint-url http://127.0.0.1:7070 s3api head-bucket --bucket local'
  assert_success
}
