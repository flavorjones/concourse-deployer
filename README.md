# Concourse::Deployer

Provides easy installation and maintenance of an opinionated [Concourse](https://concourse-ci.org) deployment.

- external Postgres database
- Github auth integration
- LetsEncrypt integration for SSL cert management
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

You can create and deploy a LetsEncrypt SSL cert:

``` sh
rake letsencrypt:create etsencrypt:backup letsencrypt:import
rake bosh:deploy
```

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
rake bbl:gcp:init[gcp_project_id]  # initialize bosh-bootloader for GCP
rake bbl:gcp:up                    # terraform your environment and deploy the bosh director
rake bosh:deploy                   # deploy concourse
rake bosh:init                     # prepare the concourse bosh deployment
rake bosh:update                   # upload stemcells and releases to the director
rake bosh:update:ubuntu_stemcell   # upload ubuntu stemcell to the director
rake letsencrypt:backup            # backup web:/etc/letsencrypt to local disk
rake letsencrypt:create            # create a cert
rake letsencrypt:import            # import letsencrypt keys into `secrets.yml` from backup
rake letsencrypt:renew             # renew the certificate
rake letsencrypt:restore           # restore web:/etc/letsencrypt from backup
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
* `letsencrypt.tar.gz` (if you're using the letsencrypt SSL cert functionality)

You will see these files listed in `.gitattributes` invoking git-crypt for them.


## Deploying to GCP

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

### Manage your letsencrypt SSL cert

``` sh
$ rake letsencrypt:backup
$ rake letsencrypt:create
$ rake letsencrypt:restore
$ rake letsencrypt:import
$ rake letsencrypt:renew
```

__NOTE:__ These tasks will create and use `letsencrypt.tar.gz` which contains sensitive data.


### Custom bosh ops files

If you want to perform any custom operations on the manifest, put them in a file named `operations.yml` and they'll be pulled in as the __final__ ops file during deployment.


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/flavorjones/concourse-deployer. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).


## TODO

- [ ] update windows stemcell
- [ ] include windows worker in manifest
- [ ] deploy windows ruby tools release to the windows vms
- [ ] +      x_frame_options: "SAMEORIGIN"
- [ ] +      container_placement_strategy: random
- [ ] enable encryption https://concourse.ci/encryption.html


Things to follow up on:

- [ ] upgrading! ZOMG
- [ ] consider swapping secrets-wizarding and rake task for deploy for a shell script that's user-modifiable
- [ ] bbl feature for suspending/unsuspending the director VM?
- [ ] stack driver add-on?
- [ ] metrics? https://concourse-ci.org/metrics.html
- [ ] credhub for credential management? https://concourse-ci.org/creds.html


Things I'm not immediately planning to do but that might be nice:

- [ ] ops file to make the cloud-config come in under default GCP quota
- [ ] ops files for a few variations on size/cost tradeoffs
