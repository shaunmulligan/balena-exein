# balena-exein

Reusable GitHub workflows that scan every balena release with
[Exein Analyzer](https://www.exein.io/platform/exein-analyzer) and only let
devices get a release after its scans pass.

```text
balena build -> Exein upload -> balena draft release -> (scans finish) -> CVE gate -> finalize
```

Exein CVE analysis can take hours, so the pipeline does not wait for it. A
balena draft release holds each build. The fleet's "track latest" policy
ignores drafts, so devices never get an ungated release. A scheduled gate
finalizes each draft when its scans pass.

Exein scans the image tarball that the build saved, and the deploy loads that
same tarball. The images Exein scans are the images that ship.

## Use it

Add two files to your balena project repo.

`.github/workflows/balena-exein-deploy.yml`:

```yaml
name: Build, scan, deploy draft

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  deploy:
    uses: shaunmulligan/balena-exein/.github/workflows/build-scan-draft.yml@v1.0.0
    with:
      fleets: |
        myorg/my-fleet-rpi5
        myorg/my-fleet-x86
    secrets:
      balena-token: ${{ secrets.BALENA_TOKEN }}
      analyzer-api-key: ${{ secrets.ANALYZER_API_KEY }}
```

`.github/workflows/balena-exein-gate.yml`:

```yaml
name: Exein gate

on:
  schedule:
    # Off the round minutes: GitHub delays or drops scheduled runs at the top of the hour.
    - cron: "7,22,37,52 * * * *"
  workflow_dispatch:
    inputs:
      enforce:
        description: Keep failing drafts unfinalized (clear to finalize them as override)
        type: boolean
        default: true

permissions:
  contents: read

jobs:
  gate:
    uses: shaunmulligan/balena-exein/.github/workflows/gate.yml@v1.0.0
    with:
      fleets: |
        myorg/my-fleet-rpi5
        myorg/my-fleet-x86
      enforce: ${{ github.event_name != 'workflow_dispatch' || inputs.enforce }}
    secrets:
      balena-token: ${{ secrets.BALENA_TOKEN }}
      analyzer-api-key: ${{ secrets.ANALYZER_API_KEY }}
```

Then add the repo secrets `BALENA_TOKEN` (balenaCloud API key) and
`ANALYZER_API_KEY` (Exein Analyzer API key).

To add a fleet, add a line to `fleets` in both files. Each fleet builds,
scans, and deploys on its own, so one failing fleet does not block the others.

## Inputs

`build-scan-draft.yml`:

| Input | Default | Description |
|---|---|---|
| `fleets` | required | Fleet slugs, one per line or comma-separated. `#` starts a comment. |
| `source` | `.` | Project directory, relative to the repo root |
| `project-name` | `app` | Local image name prefix for `balena build` |
| `object-prefix` | fleet name | Exein objects are named `<prefix>-<service>` |
| `balena-cli-version` | `v25.2.6` | balena CLI release |
| `analyzer-url` | `https://analyzer.exein.io/api/` | Analyzer API, for on-prem installs |
| `analyzer-cli-version` | `latest` | Analyzer CLI release |

`gate.yml` takes `fleets`, `balena-cli-version`, `analyzer-url` and
`analyzer-cli-version` with the same meanings, plus:

| Input | Default | Description |
|---|---|---|
| `fail-on` | `critical` | Lowest severity that blocks a release: `critical` or `high` |
| `enforce` | `true` | `false` finalizes failing drafts and tags them `override` |

Both workflows need the secrets `balena-token` and `analyzer-api-key`.

## How it works

`build-scan-draft.yml` runs one `build-scan-draft-fleet.yml` per fleet:

1. `plan` reads the fleet's device type and arch from balenaCloud and lists
   the services `balena build` creates.
2. `build` runs `balena build` on a runner that matches the arch, then saves
   one tarball per service.

   | balena arch | Runner | Emulated |
   |---|---|---|
   | `aarch64` | `ubuntu-24.04-arm` | no |
   | `amd64`, `i386`, `i386-nlp` | `ubuntu-24.04` | no |
   | `armv7hf`, `rpi` | `ubuntu-24.04` | yes, `--emulated` |

3. `scan` runs once per service. It finds or creates the Analyzer object
   `<fleet-name>-<service>`, then uploads the tarball with
   [`exein-io/analyzer-scan`](https://github.com/exein-io/analyzer-scan).
4. `deploy` loads the tarballs and runs `balena deploy --draft`. The release
   gets the tags `exein-scan-<service>=<scan-id>` and `exein-gate=pending`.

A project with no `docker-compose.yml` builds as one service named `main`,
as `balena build` does.

`gate.yml` gates each fleet's pending drafts, oldest first:

1. If a draft's scans are still running, it stops, so releases finalize in
   build order.
2. When the scans finish, it downloads each VEX and PDF report and counts
   CVEs at or above `fail-on`. It skips CVEs that Exein marks
   `not_affected`, `false_positive`, or `resolved`.
3. It attaches the VEX and report files to the release as release assets.
4. It tags the release:

   | Result | `exein-gate` | Release |
   |---|---|---|
   | No blocking CVEs | `pass` | Finalized; devices update |
   | Blocking CVEs | `fail` | Stays a draft |
   | Blocking CVEs, `enforce` false | `override` | Finalized |
   | Scan failed in Exein | `error` | Stays a draft |

   `exein-blocking` holds the count, and `exein-fail-on` holds the threshold.

## Security

- **Pin a release.** Use a tag such as `@v1.0.0` or, better, its commit SHA.
  `@main` changes under you.
- **Scope the balena key.** `balena-token` can reach every fleet its user
  can. Use a dedicated user or an organization with access to only these
  fleets.
- **Pass secrets by name.** The examples pass the two secrets explicitly, not
  with `secrets: inherit`, so the workflows get nothing else.
- **Pull requests from forks** do not get secrets, and the workflows do not
  run on `pull_request`.

## Limits

- Exein CVE analysis took 3–5 hours for a Home Assistant image, and over 40
  minutes for a 4 MB Alpine image.
- GitHub can start scheduled runs late, and disables them in a public repo
  after 60 days with no activity.
- Each scan job downloads all of its fleet's image tarballs, not only its own.

## Develop

```sh
test/gate-test.sh
test/fleet-target-test.sh
test/plan-test.sh
```

On `main`, the workflows use this repo's actions and nested workflow at
`@main`. A release must point them at the release tag, so tag with:

```sh
scripts/release.sh v1.0.0
```

The script rewrites the internal `@main` refs on a commit off `main`, signs
the commit and the tag, and moves the major tag (`v1`).

---

Co-authored with Claude
