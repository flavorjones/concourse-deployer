# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'concourse/deployer/version'

Gem::Specification.new do |spec|
  spec.name          = "concourse-deployer"
  spec.version       = Concourse::Deployer::VERSION
  spec.authors       = ["Mike Dalessio"]
  spec.email         = ["mike.dalessio@gmail.com"]

  spec.summary       = %q{Rake tasks to help BOSH-deploy a Concourse CI environment.}
  spec.description   = %q{concourse-deployer provides an ease-of-use layer on top of bosh-bootloader and bosh, to ease the initial install process and maintenance.}
  spec.homepage      = "https://github.com/flavorjones/concourse-deployer"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.14"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
