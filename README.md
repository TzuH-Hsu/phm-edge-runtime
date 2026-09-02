# phm-edge-runtime

<p align="center">
  <strong>Layered update runtime for Linux edge devices: A/B base image, signed artifact delivery, atomic switch with health-check rollback, watchdog.</strong>
</p>

<p align="center">
  <a href="https://github.com/TzuH-Hsu/phm-edge-runtime/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/TzuH-Hsu/phm-edge-runtime/actions/workflows/ci.yml/badge.svg?branch=main"></a>
  <img alt="Status" src="https://img.shields.io/badge/Status-Early-orange">
  <a href="LICENSE"><img alt="License Apache 2.0" src="https://img.shields.io/badge/License-Apache%202.0-D22128"></a>
  <img alt="Update: A/B + RAUC" src="https://img.shields.io/badge/Update-A%2FB%20%2B%20RAUC-006b75">
  <img alt="Platform: Linux" src="https://img.shields.io/badge/Platform-Linux-0e8a16">
</p>

Field-deployed edge devices fail at the worst possible moment: mid-update, with nobody on site. `phm-edge-runtime` separates what changes rarely from what changes often, and makes every switch reversible.

- **Base image** — A/B partitions, updated through RAUC. Rarely touched.
- **Application and model artifacts** — independent channels. Pull from a registry, verify the signature, switch atomically, roll back automatically when the health check fails.
- **Watchdog** — the hardware watchdog as the last line of defence.

The reason for the split is simple: a model ships far more often than an operating system, and a model update must never require rebuilding an image.

> **Status: early.** The API is not stable; expect breaking changes before `v1.0`. Language and build system are being settled — see the open issues.

## Why not just ship a whole image every time

Whole-image updates are simpler and they are the right answer for many fleets. They stop being the right answer when the thing that changes most often is a 20 MB model artifact and the image is 800 MB, when the link to the device is a metered or intermittent one, and when a failed boot means a site visit. At that point the deployment unit has to become the artifact, and the runtime has to own the switch.

## Scope

| In scope | Out of scope |
| --- | --- |
| Channel abstraction: source, verification, atomic switch, health check, rollback | Board support and image recipes (that is the Yocto layer's job) |
| Base image channel (A/B, RAUC) | Building the artifacts themselves |
| Application and model artifact channels | Anything specific to one deployment or site |
| Version matrix and compatibility rejection | Telemetry and application logic |
| Watchdog integration | |

## Getting started

```bash
make help     # all targets
make verify   # lint + tests — the gate before every PR
```

There is no published package yet. Watch [releases](https://github.com/TzuH-Hsu/phm-edge-runtime/releases) or the open issues for the first `v0.1.0`.

## Contributing

Work from an issue, branch as `<type>/<issue#>-<slug>`, use Conventional Commits, open a PR. `main` is protected: PR required, `ci` must pass. Conventions live in [`AGENTS.md`](AGENTS.md) (canonical) and [`CONTRIBUTING.md`](CONTRIBUTING.md).

Two rules are specific to this repository and non-negotiable:

- **No deployment-specific content** — no organisation names, site names, equipment models, data samples or project codenames, anywhere, including tests and fixtures.
- **No dependency on a downstream project** — applications depend on this library, never the reverse.

Contributions are provided under Apache-2.0 by default ([§5](LICENSE)). No CLA.

## Security

Signature verification and rollback are the security surface of this library. Report vulnerabilities privately — see [`SECURITY.md`](SECURITY.md). Please do not open a public issue for a suspected vulnerability.

## License

[Apache-2.0](LICENSE). Copyright 2026 Tzu-Hsuan Hsu. Attribution requirements are in [`NOTICE`](NOTICE).
