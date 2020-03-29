# Changelog for `concourse-deployer`

## v0.5.0 / 2020-03-29

Features:

- Concourse v6.0.0 support.


## v0.4.0 / 2019-11-02

Features:

- use the limit-active-tasks container placement strategy

Security:

- do not create or use a local user if a main_team is defined; avoid having a username/password account that could be brute-forced


## v0.3.0 / 2019-02-16

Features:

- Upgrade concourse-bosh-deployment to a specific version.


## v0.2.0 / 2019-02-10

Features:

- Use Caddy (via caddy-bosh-release) for managing LetsEncrypt certificates.
- `scale-vars.yml` is now `deployment-vars.yml` and presents additional customizable variables.
- New task `db:connect` for getting a postgres commandline prompt.
- New task `bosh:interpolate` for examining the final BOSH manifest


## v0.1.0 / 2019-01-04

First release.
