# Concourse::Deployer

This gem provides a set of rake tasks to ease the installation and maintenance of a bbl-deployed BOSH director, and a bosh-deployer concourse pipeline.


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

Concourse::Deployer.create_tasks!
```

And then execute:

    $ rake -T

to see commands that are available.


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/flavorjones/concourse-deployer. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

