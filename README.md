# Concourse::Deployer

Provides easy installation and maintenance of an opinionated [Concourse](https://concourse-ci.org) deployment.

- external Postgres database
- Github auth integration
- LetsEncrypt integration, via [caddy](https://caddyserver.com/) and [caddy-bosh-release](https://github.com/dpb587/caddy-bosh-release)
- Windows™ workers

Today this only supports deployment to GCP.


## TL;DR

These five commands will give you a full Concourse deployment, with user-friendly prompting for configuration to external resources like a Postgres database and Github auth.

``` sh
rake bbl:gcp:init[GCP_PROJECT_ID]
rake bbl:gcp:up
rake bosh:init
rake bosh:update
rake bosh:deploy
```

During `bbl:gcp:init` and `bosh:init` you'll be prompted interactively for any necessary information. Note that you need a DNS domain name in order for Caddy to create and manage your SSL certs.


## Requirements

This gem requires:

* `bbl` ~> 6.9.0 (https://github.com/cloudfoundry/bosh-bootloader/releases)
* `bosh` ~> 5.2.0 (https://github.com/cloudfoundry/bosh-cli/releases)
* `terraform` (https://www.terraform.io/downloads.html)
* `gcloud` (https://cloud.google.com/sdk/downloads)
* `direnv` (https://direnv.net/)
* `git-crypt` (https://www.agwa.name/projects/git-crypt/)


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'concourse-deployer'
```

And then run `bundle` or else install it directly with `gem install concourse-deployer`.


## Usage

In your Rakefile:

``` ruby
require "concourse/deployer"

Concourse::Deployer.new.create_tasks!
```

Available tasks:

``` sh
rake bbl:gcp:init[gcp_project_id]                 # initialize bosh-bootloader for GCP
rake bbl:gcp:up                                   # terraform your environment and deploy the bosh director
rake bosh:deploy                                  # deploy concourse
rake bosh:init                                    # prepare the concourse bosh deployment
rake bosh:interpolate                             # view interpolated manifest
rake bosh:update                                  # macro task for all `update` subtasks
rake bosh:update:concourse_deployment[commitish]  # update the git submodule for concourse-bosh-deployment (default: master)
rake bosh:update:ubuntu_stemcell                  # upload ubuntu stemcell to the director
rake db:connect                                   # connect to the postgres database
```

See full instructions below.


## A Note on Security

It's incredibly important that you don't risk leaking your credentials by committing them in the clear to a public git repository. This gem will use `git-crypt` to ensure files are encrypted which contain sensitive credentials.

Files which contain sensitive data:

* `service-account.key.json`
* `bbl-state.json`
* `secrets.yml`
* `cluster-creds.yml`
* the `vars` subdirectory

You will see these files listed in `.gitattributes` invoking git-crypt for them.


## Deploy to GCP

### Step 0: create a GCP project, and create and config a Postgres database

Spin up a postgres database. Note the following information as you do so:

* password
* IP address

To set up connectivity to it, we'll first create client SSL certs, then only allow access via SSL, and finally allow inbound connections from any source IP (so long as it's via SSL).

1. Under "SSL", create a client SSL cert, and download `client-key.pem`, `client-cert.pem`, and `server-ca.pem` for later use.
2. Click "Allow only secured connections"
3. Under "Authorization", add "0.0.0.0/0" as an allowed network.
4. Under "Databases", create a database named `atc`.

Using an external db is a little annoying to do, but in the opinion of the author, it's worth it to have state persisted outside of the bosh-administered cluster, so that it can be torn down and rebuilt easily when necessary.


### Step 1: Initialize bosh-bootloader and the project directory

``` sh
$ rake bbl:gcp:init[gcp_project_id]
```

This will:

* check that required dependencies are installed,
* create an `.envrc` file with environment variables for bbl to work with GCP,
* create `.gitattributes` entries to prevent sensitive files from being committed in the clear,
* create a GCP service account, associate it with your project, and give it the necessary permissions,
* and save that GCP service account information in `service-account.key.json`

__NOTE:__ At this point, if you want to use a region/zone besides us-central1, you can edit your `.envrc`.

__NOTE:__ `service-account.key.json` contains sensitive data.


### Step 2: `bbl up`

``` sh
$ rake bbl:gcp:up
```

Go get a coffee. In about 5 minutes, this will:

* terraform a GCP environment,
* spin up VMs running a bosh director and a jumpbox (a.k.a. "bastion host"),
* create a load balancer with an external IP,
* and save your state and credentials into `bbl-state.json` and the `vars` subdirectory.

__NOTE:__ This task is idempotent. If you want to upgrade your bosh director (or stemcell) using a future version of bbl, you can re-run this (but read the bbl upgrade notes first).

__NOTE:__ `bbl-state.json` and `vars` contain sensitive data.


### Step 3: Prepare the Bosh deployment for Concourse

``` sh
$ rake bosh:init
```

This will:

* create a git submodule with a clone of [`concourse-bosh-deployment`](https://github.com/concourse/concourse-bosh-deployment)
* create a `secrets.yml` file with credentials and external configuration you'll use to access concourse

You may be prompted for several things at this step, including:

* database IP and password (noted in Step 0 above)
* database server CA, client cert, and client key filenames (downloaded in Step 0 above)
* Github OAuth2 credentials


__NOTE:__ `secrets.yml` contains sensitive data.

__NOTE:__ This task is idempotent! You can re-run this whenever you like.

__NOTE:__ If you'd like a github user, team, or org to be members of Concourse's admin team, edit `secrets.yml` and add them to the `/main_team` section.


### Step 4: Upload stemcell to the director

``` sh
$ rake bosh:update
```

This will:

* upload to the director the latest GCP stemcell
* upload all necessary Bosh releases

__NOTE:__ This task is idempotent! If you want to upgrade your releases or stemcell in the future, you should re-run this.


### Step 5: deploy!

``` sh
$ rake bosh:deploy
```

This will:

* create or update a `cluster-creds.yml` file with automatically-generated cluster credentials,
* bosh-deploy Concourse

__NOTE:__ `cluster-creds.yml` and `secrets.yml` contain sensitive data.

__NOTE:__ This task is idempotent! Yay Bosh.


## Other Fun Things This Gem Does

### Scale your Concourse deployment

Your first deployment will spin up one (1) web VM, and two (2) Linux worker VMs. But you can scale these numbers up as needed by editing the file `deployment-vars.yml`, whose default contents include the values:

```yaml
---
web_instances: 1
worker_instances: 2
web_vm_type: default
worker_vm_type: default
worker_ephemeral_disk: 50GB_ephemeral_disk
```

Edit this file as appropriate for your needs, and re-run `rake bosh:deploy`.


### Custom bosh ops files

If you want to perform any custom operations on the manifest, put them in a file named `operations.yml` and they'll be pulled in as the __final__ ops file during deployment.


### Connect to the database

If you ever need to connect to the database, here's how:

``` sh
rake db:connect
```

This will:

* securely write your SSL cert, key, and CA cert to disk
* run `psql` and connect to the database
* clean up the cert and key files

Note that you will need to type in your database password; this is located in `secrets.yml`.


## Upgrade `bbl`

When a new version of bosh-bootloader comes out, just [download it](https://github.com/cloudfoundry/bosh-bootloader/releases) and make sure it's in your path as `bbl` (check by running `bbl -v`) and then:

``` sh
$ rake bbl:gcp:up
```

... which will generate a new plan and then update the jumpbox, director, and cloud config. (See https://github.com/cloudfoundry/bosh-bootloader/blob/master/docs/upgrade.md for details.)

Make sure to commit into source control all the changes in your project directory (`bbl-state.json`, `vars/`, `bosh-deployment/`, etc.).


## Upgrade `concourse-bosh-deployment`

If a new version of concourse comes out, and you'd like to upgrade, first read the [release notes for Concourse](https://concourse-ci.org/download.html) to check for any relevant breaking changes.

Then:

``` sh
$ rake bosh:update:concourse_deployment
$ rake bosh:deploy
```

If you want to pin your concourse deployment to a specific version (or branch):

``` sh
$ rake bosh:update:concourse_deployment[v5.0.0]
```

Make sure you commit to source control the updated git submodule.


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/flavorjones/concourse-deployer. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).


## TODO

- [ ] enable encryption https://concourse.ci/encryption.html
- [ ] consider swapping secrets-wizarding and rake task for deploy for a shell script that's user-modifiable
- [ ] bbl feature for suspending/unsuspending the director VM?
- [ ] stack driver add-on?
- [ ] metrics? https://concourse-ci.org/metrics.html
- [ ] credhub for credential management? https://concourse-ci.org/creds.html
