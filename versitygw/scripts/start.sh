#!/bin/sh
#ddev-generated
set -eu

VGW_ENTRYPOINT="${VGW_ENTRYPOINT:-/usr/local/bin/docker-entrypoint.sh}"
READY_TIMEOUT="${VERSITYGW_READY_TIMEOUT:-60}"
DEFAULT_BUCKET="${VERSITYGW_DEFAULT_BUCKET:-local}"
PUBLIC_READ="${VERSITYGW_PUBLIC_READ:-true}"
ROOT_ACCESS="${ROOT_ACCESS_KEY:-versity}"
ROOT_SECRET="${ROOT_SECRET_KEY:-versitysecret}"
REGION="${VGW_REGION:-us-east-1}"
ENDPOINT_URL="${VERSITYGW_ENDPOINT_URL:-http://127.0.0.1:7070}"

export AWS_ACCESS_KEY_ID="${ROOT_ACCESS}"
export AWS_SECRET_ACCESS_KEY="${ROOT_SECRET}"
export AWS_DEFAULT_REGION="${REGION}"
export AWS_EC2_METADATA_DISABLED=true
export AWS_PAGER=""

"${VGW_ENTRYPOINT}" "$@" &
vgw_pid=$!

cleanup() {
  if kill -0 "${vgw_pid}" 2>/dev/null; then
    kill "${vgw_pid}" 2>/dev/null || true
    wait "${vgw_pid}" || true
  fi
}

trap cleanup INT TERM

wait_for_s3() {
  i=0
  while [ "${i}" -lt "${READY_TIMEOUT}" ]; do
    if aws --endpoint-url "${ENDPOINT_URL}" s3api list-buckets >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "${vgw_pid}" 2>/dev/null; then
      echo "VersityGW exited before S3 API became ready" >&2
      return 1
    fi
    i=$((i + 1))
    sleep 1
  done
  echo "Timed out waiting for VersityGW S3 API" >&2
  return 1
}

ensure_bucket() {
  if aws --endpoint-url "${ENDPOINT_URL}" s3api head-bucket --bucket "${DEFAULT_BUCKET}" >/dev/null 2>&1; then
    return 0
  fi

  echo "Creating bucket: ${DEFAULT_BUCKET}"
  if [ "${REGION}" = "us-east-1" ]; then
    aws --endpoint-url "${ENDPOINT_URL}" s3api create-bucket --bucket "${DEFAULT_BUCKET}" >/dev/null
  else
    aws --endpoint-url "${ENDPOINT_URL}" s3api create-bucket \
      --bucket "${DEFAULT_BUCKET}" \
      --create-bucket-configuration "LocationConstraint=${REGION}" >/dev/null
  fi

  aws --endpoint-url "${ENDPOINT_URL}" s3api head-bucket --bucket "${DEFAULT_BUCKET}" >/dev/null
}

apply_public_policy() {
  policy_file="$(mktemp)"
  cat >"${policy_file}" <<EOF
{"Version":"2012-10-17","Statement":[{"Sid":"PublicRead","Effect":"Allow","Principal":"*","Action":["s3:GetObject"],"Resource":["arn:aws:s3:::${DEFAULT_BUCKET}/*"]}]}
EOF
  aws --endpoint-url "${ENDPOINT_URL}" s3api put-bucket-policy \
    --bucket "${DEFAULT_BUCKET}" \
    --policy "file://${policy_file}" >/dev/null
  rm -f "${policy_file}"
}

remove_public_policy() {
  if ! aws --endpoint-url "${ENDPOINT_URL}" s3api delete-bucket-policy --bucket "${DEFAULT_BUCKET}" >/dev/null 2>&1; then
    echo "No bucket policy to delete for ${DEFAULT_BUCKET}, or bucket policy already private"
  fi
}

provision_bucket() {
  if [ -z "${DEFAULT_BUCKET}" ]; then
    echo "VERSITYGW_DEFAULT_BUCKET is empty, skipping bucket provisioning"
    return 0
  fi

  echo "Ensuring bucket exists: ${DEFAULT_BUCKET}"
  ensure_bucket

  case "$(printf '%s' "${PUBLIC_READ}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on)
      echo "Applying public-read bucket policy to bucket: ${DEFAULT_BUCKET}"
      apply_public_policy
      ;;
    *)
      echo "Removing public bucket policy from bucket: ${DEFAULT_BUCKET}"
      remove_public_policy
      ;;
  esac
}

wait_for_s3
provision_bucket

wait "${vgw_pid}"
