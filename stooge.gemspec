# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "stooge/version"

Gem::Specification.new do |s|
  s.name        = "stooge"
  s.version     = Stooge::VERSION
  s.authors     = ["Niklas Holmgren"]
  s.email       = ["niklas@sutajio.se"]
  s.homepage    = "https://github.com/sutajio/stooge"
  s.summary     = %q{Super advanced job queue over AMQP}
  s.description = %q{Super advanced job queue over AMQP}

  s.rubyforge_project = "stooge"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency 'amqp'
  s.add_dependency 'em-synchrony'
  s.add_dependency 'multi_json'
  s.add_development_dependency 'rspec'

end
