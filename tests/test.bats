#!/usr/bin/env bats

setup() {
  set -eu -o pipefail

  export GITHUB_REPO=rexlManu/ddev-versitygw

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH:-}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"
  mkdir -p "${HOME}/tmp"
  export TESTDIR="$(mktemp -d "${HOME}/tmp/${PROJNAME}.XXXXXX")"
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site
  assert_success
  run ddev start -y
  assert_success
}

health_checks() {
  run ddev exec -s versitygw versitygw --version
  assert_success
  assert_output --partial "Version"

  run ddev exec -s versitygw sh -lc 'AWS_ACCESS_KEY_ID=versity AWS_SECRET_ACCESS_KEY=versitysecret AWS_DEFAULT_REGION=us-east-1 AWS_EC2_METADATA_DISABLED=true aws --endpoint-url http://127.0.0.1:7070 s3api list-buckets'
  assert_success
  assert_output --partial "\"Name\": \"local\""

  run ddev exec -s versitygw sh -lc 'AWS_ACCESS_KEY_ID=versity AWS_SECRET_ACCESS_KEY=versitysecret AWS_DEFAULT_REGION=us-east-1 AWS_EC2_METADATA_DISABLED=true aws --endpoint-url http://127.0.0.1:7070 s3api get-bucket-policy --bucket local'
  assert_success
  assert_output --partial "PublicRead"

  run ddev exec -s versitygw sh -lc 'printf hello > /tmp/test.txt && AWS_ACCESS_KEY_ID=versity AWS_SECRET_ACCESS_KEY=versitysecret AWS_DEFAULT_REGION=us-east-1 AWS_EC2_METADATA_DISABLED=true aws --endpoint-url http://127.0.0.1:7070 s3 cp /tmp/test.txt s3://local/test.txt'
  assert_success

  run curl -k -fsSI "https://${PROJNAME}.ddev.site:17080"
  assert_success
  assert_output --partial "200"

  run curl -k -sS -o /dev/null -w "%{http_code}" "https://${PROJNAME}.ddev.site:17070/"
  assert_success
  [[ "${output}" =~ ^(200|400|403|405)$ ]]

  run curl -k -sS -o /dev/null -w "%{http_code}" "https://${PROJNAME}.ddev.site:17071/"
  assert_success
  [[ "${output}" =~ ^(200|400|401|403|404|405|500)$ ]]

  run curl -k -fsS "https://${PROJNAME}.ddev.site:17070/local/test.txt"
  assert_success
  assert_output "hello"

  run ddev describe -j
  assert_success
  assert_output --partial "\"service\":\"versitygw\""
  assert_output --partial "https://${PROJNAME}.ddev.site:17080"
  assert_output --partial "https://${PROJNAME}.ddev.site:17070"
  assert_output --partial "Default bucket: local"
}

teardown() {
  set -eu -o pipefail
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1
  if [ -n "${GITHUB_ENV:-}" ]; then
    [ -e "${GITHUB_ENV:-}" ] && echo "TESTDIR=${HOME}/tmp/${PROJNAME}" >> "${GITHUB_ENV}"
  else
    [ "${TESTDIR}" != "" ] && rm -rf "${TESTDIR}"
  fi
}

@test "install from directory" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}
