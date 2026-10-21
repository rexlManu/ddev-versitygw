[![add-on registry](https://img.shields.io/badge/DDEV-Add--on_Registry-blue)](https://addons.ddev.com)
[![tests](https://github.com/rexlManu/ddev-versitygw/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/rexlManu/ddev-versitygw/actions/workflows/tests.yml?query=branch%3Amain)
[![release](https://img.shields.io/github/v/release/rexlManu/ddev-versitygw)](https://github.com/rexlManu/ddev-versitygw/releases/latest)

# ddev-versitygw

Local S3 storage for DDEV, with [VersityGW](https://github.com/versity/versitygw). Requires DDEV 1.25.2 or newer.

## Install

Run these commands in your DDEV project:

```bash
ddev add-on get rexlManu/ddev-versitygw
ddev restart
```

For Laravel 12 and 13, that is all the setup you need. The add-on:

- Creates the `local` bucket and allows public object reads.
- Sets Laravel's default disk to `s3` inside DDEV.
- Installs `league/flysystem-aws-s3-v3` if it is missing. This changes `composer.json` and `composer.lock`.
- Adds a DDEV-only option to `config/filesystems.php` so copies and moves work without object ACL reads.
- Clears Laravel's configuration cache so the local settings take effect.

DDEV supplies the storage settings through the web container's environment. Your app's `.env` file keeps its existing storage settings. Composer must be able to download packages on the first restart. Later restarts skip installation when the adapter is present.

Commit the installed add-on files under `.ddev/`, plus the changes to `composer.json`, `composer.lock`, and `config/filesystems.php`.

## Use with Laravel

Use Laravel's storage API as usual:

```php
use Illuminate\Support\Facades\Storage;

Storage::put('hello.txt', 'Hello from Laravel');
Storage::get('hello.txt');
Storage::url('hello.txt');
Storage::temporaryUrl('hello.txt', now()->addMinutes(5));
```

The add-on uses the routed S3 endpoint for PHP and signed URLs. `AWS_URL=null` lets Laravel build public URLs from that endpoint and encode file names. Public URLs and signed URLs work in the browser. DDEV's local certificate must be trusted, as with your project's main HTTPS URL.

Other DDEV project types can use the same S3 service and `AWS_*` environment variables. The Laravel setup script does nothing if the Composer root has no `artisan` file.

## Web UI and CLI

```bash
ddev versitygw
ddev versitygw-aws s3 ls
ddev versitygw-aws s3 ls s3://local
ddev describe
```

Default login:

- Access key: `versity`
- Secret key: `versitysecret`
- Region: `us-east-1`

Replace `<project>` with your DDEV hostname:

| Service | URL |
| --- | --- |
| Web UI | `https://<project>.ddev.site:17080` |
| S3 API | `https://<project>.ddev.site:17070` |
| Admin API | `https://<project>.ddev.site:17071` |
| S3 inside the DDEV network | `http://versitygw:7070` |

The web UI uses HTTPS endpoints to avoid mixed-content errors. These are local development credentials and the default bucket permits anonymous downloads.

## Customize

Set options in `.ddev/.env.versitygw`, then restart:

```bash
ddev dotenv set .ddev/.env.versitygw --versitygw-default-bucket=assets
ddev dotenv set .ddev/.env.versitygw --versitygw-region=eu-central-1
ddev restart
```

The bucket, Laravel settings, and CLI credentials all use the same options:

| Variable | Default | Purpose |
| --- | --- | --- |
| `VERSITYGW_ACCESS_KEY` | `versity` | S3 and web UI access key |
| `VERSITYGW_SECRET_KEY` | `versitysecret` | S3 and web UI secret key |
| `VERSITYGW_REGION` | `us-east-1` | S3 region |
| `VERSITYGW_DEFAULT_BUCKET` | `local` | Bucket to create on startup |
| `VERSITYGW_PUBLIC_READ` | `true` | Allow anonymous object downloads |
| `VERSITYGW_FILESYSTEM_DISK` | `s3` | Default Laravel disk inside DDEV |
| `VERSITYGW_LARAVEL_AUTO_SETUP` | `true` | Install the S3 adapter and configure copies and moves |
| `VERSITYGW_DOCKER_IMAGE` | [Pinned image](versitygw/Dockerfile) | Upstream image to build from |

To keep Laravel's local disk as its default, set `VERSITYGW_FILESYSTEM_DISK=local`. You can still use `Storage::disk('s3')`.

To manage Laravel setup yourself, set `VERSITYGW_LARAVEL_AUTO_SETUP=false` and run:

```bash
ddev composer require 'league/flysystem-aws-s3-v3:^3.0'
```

Add this option to the `s3` disk in `config/filesystems.php` to support copies and moves:

```php
'retain_visibility' => env('VERSITYGW_RETAIN_VISIBILITY', true),
```

The add-on sets `VERSITYGW_RETAIN_VISIBILITY=false` inside DDEV. Outside DDEV, the default stays `true`. VersityGW's POSIX backend uses bucket policies and does not support per-object ACL operations such as `Storage::visibility()` or `Storage::setVisibility()`.

To use private storage, set `VERSITYGW_PUBLIC_READ=false`. The next restart removes the default bucket's policy. Use signed URLs to download private files. The add-on manages the entire policy of the default bucket, so use a separate bucket for custom policies.

DDEV provides these environment variables to the web container. They override the same keys in Laravel's `.env` file:

```env
FILESYSTEM_DISK=s3
AWS_ACCESS_KEY_ID=versity
AWS_SECRET_ACCESS_KEY=versitysecret
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=local
AWS_USE_PATH_STYLE_ENDPOINT=true
AWS_ENDPOINT=https://<project>.ddev.site:17070
AWS_URL=null
```

## Data and upgrades

Objects, version history, and IAM settings persist in the `versitygw-s3`, `versitygw-versioning`, and `versitygw-iam` Docker volumes. Restarting or updating the add-on keeps these volumes.

To update:

```bash
ddev add-on get rexlManu/ddev-versitygw
ddev restart
```

The default image is pinned in [versitygw/Dockerfile](versitygw/Dockerfile). Check the [upstream release notes](https://github.com/versity/versitygw/releases) before an image upgrade. For upgrades from before VersityGW 1.9.0, users who enabled Object Lock must follow the [retention migration notes](https://github.com/versity/versitygw/discussions/2521). The default add-on setup does not enable Object Lock.

## Troubleshoot

```bash
ddev logs -s versitygw
ddev versitygw-aws s3api list-buckets
ddev exec curl -fsS http://versitygw:7070/health
```

DDEV waits until the S3 service and default bucket are ready. A provisioning error causes startup to fail instead of leaving a service that looks ready.

If Composer cannot install the S3 adapter, fix the reported dependency or network error, then run `ddev restart` again.

## Develop this add-on

See [CONTRIBUTING.md](CONTRIBUTING.md) for local tests and the Laravel demo test.
