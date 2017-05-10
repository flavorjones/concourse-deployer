# Concourse::Deployer

This gem provides a set of rake tasks to ease the installation and maintenance of a bbl-deployed bosh director, and a bosh-deployed concourse environment.

__NOTE:__ I'm practicing README-driven development, so until I actually cut a release, YMMV.


## TL;DR

These five commands will give you a full concourse deployment:

``` sh
rake bbl:gcp:init[your-unique-gcp-project-name]
rake bbl:gcp:up
rake bosh:init[your-concourse-url]
rake bosh:update
rake bosh:deploy
```


## Requirements

This gem requires:

* `bbl` ~> 3.0.2 (https://github.com/cloudfoundry/bosh-bootloader/releases)
* `bosh` ~> 2.0 (https://github.com/cloudfoundry/bosh-cli/releases)
* `terraform` (https://www.terraform.io/downloads.html)

If you're deploying to GCP, this gem also requires:

* `gcloud` (https://cloud.google.com/sdk/downloads)

Finally, it's recommended that you use:

* `direnv` (https://direnv.net/)


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
rake bosh:cloud-config:download    # download the bosh cloud config to `cloud-config.yml`
rake bosh:cloud-config:upload      # upload a bosh cloud config from `cloud-config.yml`
rake bosh:concourse:backup         # backup your concourse database to `concourse.atc.pgdump`
rake bosh:concourse:restore        # restore your concourse database from `concourse.atc.pgdump`
rake bosh:deploy                   # deploy concourse
rake bosh:init[dns_name]           # prepare a bosh manifest for your concourse deployment
rake bosh:update                   # upload stemcells and releases to the director
rake letsencrypt:backup            # backup web:/etc/letsencrypt to local disk
rake letsencrypt:import            # import letsencrypt keys into `private.yml` from backup
rake letsencrypt:renew             # renew the certificate
rake letsencrypt:restore           # restore web:/etc/letsencrypt from backup
```

## A Note on Security

It's incredibly important that you don't leak your credentials by committing them to a public git repository. This gem will `.gitignore` a set of files that contain sensitive credentials. However, this means you'll need to find your own way to keep them private and safe (I recommend a password vault).

Files it's OK to commit to a public repo, because they contain no sensitive data:

* `.envrc`
* `concourse.yml`
* `cloud-config.yml`

Files it's NOT OK to be public, because they contain sensitive data:

* `service-account.key.json`
* `bbl-state.json`
* `private.yml`
* `concourse.atc.pgdump`
* `letsencrypt/`


## Deploying to GCP

### Step 1: initialize

``` sh
$ rake bbl:gcp:init[your-unique-gcp-project-name]
```

This will:

* create `.gitignore` entries to prevent sensitive files from being committed,
* check that required dependencies are installed,
* create an `.envrc` file with environment variables for bbl to work with GCP,
* create a GCP service account, associate it with your project, and give it the necessary permissions,
* and save that GCP service account information in `service-account.key.json`

__NOTE:__ At this point, if you want to use a region/zone besides us-east1/us-east1-b, you can edit your `.envrc`.

__NOTE:__ `service-account.key.json` is sensitive and should NOT be committed to a public repo.

### Step 2: bbl up

``` sh
$ rake bbl:gcp:up
```

Go get a coffee. In about 5 minutes, this will:

* terraform a GCP environment,
* with a VM running a bosh director,
* put a load balancer in front of it, ready for concourse to be installed,
* and save your state and credentials into `bbl-state.json`.

__NOTE:__ This task is idempotent! If you want to upgrade your bosh director (or stemcell) using a future version of bbl, you should re-run this.

__NOTE:__ `bbl-state.json` is sensitive and should NOT be committed to a public repo.


### Step 3: prepare a bosh manifest for your concourse deployment

``` sh
$ rake bosh:init[your-concourse-domain]
```

This will:

* generate a bosh manifest, `concourse.yml`, to deploy concourse
* automatically generate all credentials (including key pairs),
* and save those credentials to `private.yml`.

__NOTE:__ `<your-concourse-domain>` is the DNS hostname at which concourse will be running

__NOTE:__ `concourse.yml` can and should be edited by you!

__NOTE:__ `private.yml` is sensitive and should NOT be committed to a public repo.


### Step 4: upload releases and stemcell to the director

``` sh
$ rake bosh:update
```

This will:

* upload to the director the latest bosh releases for concourse and runC
* upload to the director the latest gcp lite stemcell

__NOTE:__ This task is idempotent! If you want to upgrade your releases or stemcell in the future, you should re-run this.


### Step 5: deploy!

``` sh
$ rake bosh:deploy
```

This will deploy `concourse.yml` using the credentials set in `private.yml`.

__NOTE:__ This task is idempotent! Yay bosh. Edit `concourse.yml` and re-run this task to update your deployment.


## Other Fun Things This Gem Does

### Backup and restore of your concourse database:

``` sh
$ rake bosh:concourse:backup
$ rake bosh:concourse:restore
```

__NOTE:__ The backup file, `concourse.atc.pgdump`, may contain sensitive data from your concourse pipelines and should NOT be committed to a public git repo.


### Download and Upload a bosh cloud config

Occasionally it's useful to modify the cloud config.

``` sh
$ rake bosh:cloud-config:download
$ rake bosh:cloud-config:upload
```

__NOTE:__ The cloud config file, `cloud-config.yml` does not contain credentials and is OK to commit to a repository if you like.


### Manage SSH keys from letsencrypt

``` sh
$ rake letsencrypt:backup
$ rake letsencrypt:restore
$ rake letsencrypt:import
$ rake letsencrypt:renew
```


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/flavorjones/concourse-deployer. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).


## TODO

Things remaining to do:

- [x] generate credentials
- [ ] update windows stemcell
- [ ] an ops file for a windows worker
- [ ] concourse:backup and concourse:restore
- [ ] cloud-config:download and cloud-config:upload (do we really need this?)
- [ ] letsencrypt certificate actions
- [ ] consider requiring and using git-crypt for sensitive information
