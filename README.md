# Concourse::Deployer

This gem provides a set of rake tasks to ease the installation and maintenance of a `bbl`-deployed Bosh director, and a Bosh-deployed Concourse environment.


## TL;DR

These five commands will give you a full concourse deployment:

``` sh
rake bbl:gcp:init[GCP_PROJECT_ID]
rake bbl:gcp:up
rake bosh:init or rake bosh:init[DNS_NAME]
rake bosh:update
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
rake bbl:gcp:init[gcp_project_id]           # initialize bosh-bootloader for GCP
rake bbl:gcp:up                             # terraform your environment and deploy the bosh director
rake bosh:cloud-config:download             # download the bosh cloud config to `cloud-config.yml`
rake bosh:cloud-config:upload               # upload a bosh cloud config from `cloud-config.yml`
rake bosh:concourse:backup                  # backup your concourse database to `concourse.pg.gz`
rake bosh:concourse:restore                 # restore your concourse database from `concourse.pg.gz`
rake bosh:deploy                            # deploy concourse
rake bosh:init[dns_name]                    # prepare a bosh manifest for your concourse deployment
rake bosh:update                            # upload stemcells and releases to the director
rake bosh:update:concourse_release          # upload concourse release to the director
rake bosh:update:concourse_windows_release  # upload concourse windows release to the director
rake bosh:update:garden_runc_release        # upload garden release to the director
rake bosh:update:postgres_release           # upload postgres release to the director
rake bosh:update:ubuntu_stemcell            # upload ubuntu stemcell to the director
rake bosh:update:windows_ruby_dev_tools     # upload windows-ruby-dev-tools release to the director
rake bosh:update:windows_utilities_release  # upload windows-utilities release to the director
rake bosh:update:windows_stemcell           # upload windows stemcell to the director
rake letsencrypt:backup                     # backup web:/etc/letsencrypt to local disk
rake letsencrypt:create                     # create a cert
rake letsencrypt:import                     # import letsencrypt keys into `secrets.yml` from backup
rake letsencrypt:renew                      # renew the certificate
rake letsencrypt:restore                    # restore web:/etc/letsencrypt from backup
```

## A Note on Security

It's incredibly important that you don't risk leaking your credentials by committing them in the clear to a public git repository. This gem will use `git-crypt` to ensure the files are encrypted that contain sensitive credentials.

Files that contain sensitive data:

* `bbl-state.json`
* `secrets.yml`
* `cluster-creds.yml`
* `service-account.key.json`
* the `vars` subdirectory

You will see these files listed in `.gitattributes` invoking git-crypt for them.

* TODO `concourse.atc.pg.gz` ?
* TODO `letsencrypt.tar.gz` ?


## Deploying to GCP

### Step 0: create a postgres database on GCP

Note the following information:

* password
* IP address


### Step 1: initialize

``` sh
$ rake bbl:gcp:init[your-unique-gcp-project-name]
```

This will:

* check that required dependencies are installed,
* create an `.envrc` file with environment variables for bbl to work with GCP,
* create `.gitattributes` entries to prevent sensitive files from being committed,
* create a GCP service account, associate it with your project, and give it the necessary permissions,
* and save that GCP service account information in `service-account.key.json`

__NOTE:__ At this point, if you want to use a region/zone besides us-central1, you can edit your `.envrc`.

__NOTE:__ `service-account.key.json` contains sensitive data.


### Step 2: bbl up

``` sh
$ rake bbl:gcp:up
```

Go get a coffee. In about 5 minutes, this will:

* terraform a GCP environment,
* spin up VMs running a bosh director and a jumpbox (a.k.a. "bastion host"),
* create a load balancer with an external IP,
* and save your state and credentials into `bbl-state.json` and the `vars` subdirectory.

__NOTE:__ This task is idempotent. If you want to upgrade your bosh director (or stemcell) using a future version of bbl, you can re-run this (but read the bbl upgrade notes first).

__NOTE:__ `bbl-state.json` contains sensitive data.


### Step 3: prepare the concourse bosh deployment

``` sh
$ rake bosh:init
```

This will:

* clone a git submodule with a version of `concourse-bosh-deployment`
* create a `secrets.yml` file with credentials and external configuration you'll use to access concourse

__NOTE:__ `secrets.yml` contains sensitive data.

__NOTE:__ This task is idempotent! You can re-run this whenever you like.


### Step 4: upload releases and stemcell to the director

``` sh
$ rake bosh:update
```

This will:

* upload to the director the latest bosh releases for concourse, runC, and others
* upload to the director the latest GCP stemcells
* create or update a `cluster-creds.yml` file with cluster credentials

__NOTE:__ `cluster-creds.yml` contains sensitive data.

__NOTE:__ This task is idempotent! If you want to upgrade your releases or stemcell in the future, you should re-run this.


### Step 5: deploy!

``` sh
$ rake bosh:deploy
```

This will:

* automatically generate all credentials (including key pairs and a self-signed cert),
* and save those credentials to `secrets.yml`.
* deploy `concourse.yml` using the credentials set in `secrets.yml`.

__NOTE:__ `secrets.yml` is sensitive and should NOT be committed to a public repo.

__NOTE:__ This task is idempotent! Yay bosh. Edit `concourse.yml` and re-run this task to update your deployment.


## Other Fun Things This Gem Does

### Backup and restore of your concourse database:

``` sh
$ rake bosh:concourse:backup
$ rake bosh:concourse:restore
```

__NOTE:__ The backup file, `concourse.atc.pg.gz`, may contain sensitive data from your concourse pipelines and should NOT be committed to a public git repo.


### Download and Upload a bosh cloud config

Occasionally it's useful to modify the cloud config.

``` sh
$ rake bosh:cloud-config:download
$ rake bosh:cloud-config:upload
```

__NOTE:__ The cloud config file, `cloud-config.yml` does not contain credentials and is OK to commit to a repository if you like.


### Manage your letsencrypt SSL cert

``` sh
$ rake letsencrypt:backup
$ rake letsencrypt:create
$ rake letsencrypt:restore
$ rake letsencrypt:import
$ rake letsencrypt:renew
```

__NOTE:__ These tasks will create and use `letsencrypt.tar.gz` containing your cert's private key, which should NOT be committed to a public git repo.


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/flavorjones/concourse-deployer. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).


## TODO

Things remaining to do:

- [x] use external postgres database
- [x] use DNS name
- [ ] test letsencrypt certificate tasks
- [ ] update windows stemcell
- [ ] include windows worker in manifest
- [ ] deploy windows ruby tools release to the windows vms

Things to follow up on:

- [ ] use external postgres database SSL certs
- [ ] bbl feature for suspending/unsuspending the director VM?
- [ ] stack driver add-on
- [ ] atc encryption key https://concourse.ci/encryption.html

Things I'm not immediately planning to do but that might be nice:

- [ ] ops file to make the cloud-config come in under default GCP quota
- [ ] ops files for a few variations on size/cost tradeoffs
- [ ] deploy credhub and integrate it


## Deployment Costs

see https://cloud.google.com/compute/pricing

use f1-micros for workers, and turn off the bosh director:

- bosh director: turn it off when not deploying or updating!
- atc/tsa: f1-micro: $4.09
- 4 workers f1-micro: 4 x $4.09
- db: g1-small: $13.80 (cannot run in f1-micro memory)
- TOTAL: $34.25 / month
