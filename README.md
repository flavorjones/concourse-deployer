# Concourse::Deployer

This gem provides a set of rake tasks to ease the installation and maintenance of a bbl-deployed bosh director, and a bosh-deployed concourse environment.


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
```

### A Note on Security

It's incredibly important that you don't leak your credentials by committing them to a public git repository. This gem will `.gitignore` a set of files that contain sensitive credentials. However, this means you'll need to find your own way to keep them private and safe (I recommend a password vault).

Files it's OK to commit:

* `.envrc`


### Deploying to GCP

#### Step 1: initialize

``` sh
$ rake bbl:gcp:init[your-unique-gcp-project-name]
```

This will:

* create `.gitignore` entries to prevent sensitive files from being committed
* check that required dependencies are installed
* create an `.envrc` file with environment variables for bbl to work with GCP
* create a GCP service account, associate it with your project, and give it the necessary permissions
* ... and save that GCP service account information in `service-account.key.json`

At this point, if you want to use a region/zone besides us-east1/us-east1-b, you can edit your `.envrc`.


#### Step 2: bbl up

``` sh
$ rake bbl:gcp:up
```

Go get a coffee. In about 5 minutes, you'll have:

* a terraformed GCP environment,
* with a VM running a bosh director,
* and a load balancer in front of it, ready for concourse to be installed

This task is idempotent! In fact, in the future if you want to upgrade your bosh director (or stemcell), you should re-run this.


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/flavorjones/concourse-deployer. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

