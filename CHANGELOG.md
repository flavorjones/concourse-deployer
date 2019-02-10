# Changelog for `concourse-deployer`

## v0.2.0 / 2019-02-10

Features:

- Use Caddy (via caddy-bosh-release) for managing LetsEncrypt certificates.
- `scale-vars.yml` is now `deployment-vars.yml` and presents additional customizable variables.
- New task `db:connect` for getting a postgres commandline prompt.
- New task `bosh:interpolate` for examining the final BOSH manifest


## v0.1.0 / 2019-01-04

First release.
