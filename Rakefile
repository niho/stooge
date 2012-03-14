require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

$LOAD_PATH.unshift 'lib'

task :default => [:spec]

RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = '--color'
  t.pattern = 'spec/**/*_spec.rb'
end
