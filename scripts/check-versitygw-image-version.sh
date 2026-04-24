#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

canonical_image="$(sed -n 's/^ARG BASE_IMAGE="\([^"]*\)"/\1/p' versitygw/Dockerfile)"

if [[ -z "${canonical_image}" ]]; then
  echo "Could not determine canonical BASE_IMAGE from versitygw/Dockerfile" >&2
  exit 1
fi

files=(
  "docker-compose.versitygw.yaml"
  "install.yaml"
  "README.md"
  "versitygw/Dockerfile"
)

status=0

for file in "${files[@]}"; do
  while IFS=: read -r lineno found; do
    [[ -n "${lineno:-}" ]] || continue
    if [[ "${found}" != "${canonical_image}" ]]; then
      echo "${file}:${lineno}: expected ${canonical_image} but found ${found}" >&2
      status=1
    fi
  done < <(rg -n -o 'ghcr\.io/versity/versitygw:v[0-9.]+' "${file}")
done

if [[ "${status}" -ne 0 ]]; then
  echo "VersityGW image references are out of sync." >&2
  exit "${status}"
fi

echo "VersityGW image references match ${canonical_image}."
