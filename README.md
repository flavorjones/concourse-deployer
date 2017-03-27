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

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install concourse-deployer


## Usage

In your Rakefile:

``` ruby
require "concourse/deployer"

Concourse::Deployer.new.create_tasks!
```

And then execute:

    $ rake -T

to see commands that are available.


### A Note on Security

It's incredibly important that you don't leak your credentials by committing them to a public git repository. This gem will add a set of files containing sensitive credentials to `.gitignore`. However, this means you'll need to find your own way to keep them safe (I recommend a password safe).

__Make sure you run the "init" task for your particular IaaS to add these files to your .gitignore.__

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

* a terraformed GCP environment in us-east1-b
* with a VM running a bosh director,
* and a load balancer in front of it, ready for concourse to be installed

This task is idempotent! In fact, in the future if you want to upgrade your bosh director (or stemcell), you should re-run this.


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/flavorjones/concourse-deployer. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

