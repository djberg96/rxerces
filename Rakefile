require "bundler/gem_tasks"
require "rake/extensiontask"
require "rspec/core/rake_task"

Rake::ExtensionTask.new("rxerces") do |ext|
  ext.lib_dir = "lib/rxerces"
end

RSpec::Core::RakeTask.new(:spec)

task default: [:compile, :spec]
