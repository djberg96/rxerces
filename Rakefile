require "bundler/gem_tasks"
require "rake/extensiontask"
require "rspec/core/rake_task"
require "rake/clean"
require "rbconfig"
include RbConfig

CLEAN.include(
  '**/*.gem',               # Gem files
  '**/*.rbc',               # Rubinius
  '**/*.o',                 # C object file
  '**/*.log',               # Ruby extension build log
  '**/*.lock',              # Gemfile.lock
  '**/Makefile',            # C Makefile
  '**/conftest.dSYM',       # OS X build directory
  "**/*.#{CONFIG['DLEXT']}" # C shared object
)

Rake::ExtensionTask.new("rxerces") do |ext|
  ext.lib_dir = "lib/rxerces"
end

RSpec::Core::RakeTask.new(:spec)

task default: [:compile, :spec]
