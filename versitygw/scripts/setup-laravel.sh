#!/usr/bin/env bash
#ddev-generated
set -euo pipefail

cd "${DDEV_COMPOSER_ROOT:-/var/www/html}"

# Other project types can use the S3 service without Laravel setup.
if [[ ! -f artisan || ! -f composer.json ]]; then
  exit 0
fi

case "${VERSITYGW_LARAVEL_AUTO_SETUP:-true}" in
  1|true|yes|on)
    if ! php -r '
      if (!is_file("vendor/autoload.php")) { exit(1); }
      require "vendor/autoload.php";
      exit(class_exists(League\Flysystem\AwsS3V3\AwsS3V3Adapter::class) ? 0 : 1);
    '; then
      echo "VersityGW: installing the Laravel S3 adapter."
      composer require 'league/flysystem-aws-s3-v3:^3.0' --no-interaction --no-progress
    fi
    php /mnt/ddev_config/versitygw/scripts/configure-laravel.php
    ;;
esac

# Cached configuration can still contain the previous storage settings.
if [[ -f vendor/autoload.php ]]; then
  php artisan config:clear --quiet
fi
