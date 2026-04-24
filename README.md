[![add-on registry](https://img.shields.io/badge/DDEV-Add--on_Registry-blue)](https://addons.ddev.com)
[![tests](https://github.com/rexlManu/ddev-versitygw/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/rexlManu/ddev-versitygw/actions/workflows/tests.yml?query=branch%3Amain)
[![last commit](https://img.shields.io/github/last-commit/rexlManu/ddev-versitygw)](https://github.com/rexlManu/ddev-versitygw/commits)
[![release](https://img.shields.io/github/v/release/rexlManu/ddev-versitygw)](https://github.com/rexlManu/ddev-versitygw/releases/latest)

# ddev-versitygw

`ddev-versitygw` adds [VersityGW](https://github.com/versity/versitygw) to a DDEV project as a local S3-compatible object store. The default setup is tuned for Laravel apps that use Flysystem S3 locally.

It exposes three routed endpoints that are reachable over both HTTP and HTTPS:

- S3 API on `https://<project>.ddev.site:17070`
- Admin API on `https://<project>.ddev.site:17071`
- WebUI on `https://<project>.ddev.site:17080`

The container itself is reachable inside the DDEV network as `http://versitygw:7070`, which is the endpoint Laravel should use.

## Installation

```bash
ddev add-on get rexlManu/ddev-versitygw
ddev restart
```

For local development of this add-on itself:

```bash
ddev add-on get /path/to/ddev-versitygw
ddev restart
```

After installation, commit the generated `.ddev/docker-compose.versitygw.yaml` and `.ddev/versitygw/` files in the consuming project.

## First-Run Provisioning

On every start, the addon waits for VersityGW to become reachable and then performs idempotent provisioning:

- ensures the default bucket exists
- optionally applies a public-read bucket policy to that bucket

With the defaults, a fresh install is ready for Laravel public asset usage without manual bucket or bucket-policy setup.

## Laravel Usage

Use these values in the consuming Laravel app:

```env
FILESYSTEM_DISK=s3
AWS_ACCESS_KEY_ID=versity
AWS_SECRET_ACCESS_KEY=versitysecret
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=local
AWS_USE_PATH_STYLE_ENDPOINT=true
AWS_ENDPOINT=http://versitygw:7070
AWS_URL=https://<project>.ddev.site:17070/local
```

Notes:

- `AWS_ENDPOINT` uses the internal DDEV service hostname so PHP inside the web container can reach VersityGW directly.
- `AWS_USE_PATH_STYLE_ENDPOINT=true` is important for local S3 compatibility.
- The default `local` bucket is provisioned automatically by the add-on.
- With `VERSITYGW_PUBLIC_READ=true`, objects in that bucket are publicly readable via `AWS_URL`.

## Endpoints

Replace `<project>` with your real DDEV project name.

| Surface | URL |
| ------- | --- |
| S3 API | `https://<project>.ddev.site:17070` |
| Admin API | `https://<project>.ddev.site:17071` |
| WebUI | `https://<project>.ddev.site:17080` |
| Internal Laravel endpoint | `http://versitygw:7070` |

The credentials shown by `ddev describe` default to:

- Access key: `versity`
- Secret key: `versitysecret`
- Region: `us-east-1`

## Persistence

The add-on stores object data, versioning data, and IAM data in named Docker volumes:

- `versitygw-s3`
- `versitygw-versioning`
- `versitygw-iam`

This keeps local data out of the application repository while persisting across `ddev restart`.

## Customization

Override image or credentials with a project-level `.ddev/.env.versitygw` file:

```bash
ddev dotenv set .ddev/.env.versitygw --versitygw-docker-image="ghcr.io/versity/versitygw:v1.4.1"
ddev dotenv set .ddev/.env.versitygw --versitygw-access-key="versity"
ddev dotenv set .ddev/.env.versitygw --versitygw-secret-key="versitysecret"
ddev dotenv set .ddev/.env.versitygw --versitygw-region="us-east-1"
ddev dotenv set .ddev/.env.versitygw --versitygw-default-bucket="local"
ddev dotenv set .ddev/.env.versitygw --versitygw-public-read="true"
ddev restart
```

Available variables:

| Variable | Default |
| -------- | ------- |
| `VERSITYGW_DOCKER_IMAGE` | `ghcr.io/versity/versitygw:v1.4.1` |
| `VERSITYGW_ACCESS_KEY` | `versity` |
| `VERSITYGW_SECRET_KEY` | `versitysecret` |
| `VERSITYGW_REGION` | `us-east-1` |
| `VERSITYGW_DEFAULT_BUCKET` | `local` |
| `VERSITYGW_PUBLIC_READ` | `true` |

## Verification

Useful checks in a consuming project:

```bash
ddev describe
ddev logs -s versitygw
curl -k -I https://<project>.ddev.site:17080
```

To verify public asset behavior end to end, write a file into the configured bucket and fetch it via `AWS_URL/<key>`.

## Upstream Notes

This add-on uses the published VersityGW container image and its documented environment-driven startup contract:

- `VGW_BACKEND=posix`
- `VGW_PORT`, `VGW_ADMIN_PORT`, `VGW_WEBUI_PORT`
- `VGW_IAM_DIR`, `VGW_VERSIONING_DIR`
- `VGW_WEBUI_GATEWAYS`, `VGW_WEBUI_ADMIN_GATEWAYS`
- `ROOT_ACCESS_KEY`, `ROOT_SECRET_KEY`

The add-on image layers the AWS CLI on top of the published VersityGW image so it can provision the default bucket and public-read policy automatically at startup using standard S3 API calls.

Default image pin: `ghcr.io/versity/versitygw:v1.4.1`

## Contributing

Local validation workflow:

```bash
ddev add-on get /path/to/ddev-versitygw
ddev restart
```

Then verify:

- the `versitygw` service is present in `ddev describe`
- the default bucket is provisioned automatically
- a public object URL works through the routed endpoint

The GitHub Actions matrix in `.github/workflows/tests.yml` is the canonical CI coverage for the add-on.

## Release Checklist

For a publishable release:

1. Push the repository to `rexlManu/ddev-versitygw`.
2. Make sure the repository description and `ddev-get` topic are set on GitHub.
3. Let the `tests` workflow pass on `main`.
4. Create a GitHub release with a semver tag.
5. After the release is live, verify `ddev add-on get rexlManu/ddev-versitygw` in a fresh DDEV project.
