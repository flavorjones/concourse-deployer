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


### Security

It's incredibly important that you don't leak your credentials by committing them to a public git repository. This gem will add a set of files containing sensitive credentials to `.gitignore`. However, this means you'll need to find your own way to keep them safe (I recommend a password safe).

__Make sure you run the "init" task for your particular IaaS to add these files to your .gitignore.__


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/flavorjones/concourse-deployer. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

