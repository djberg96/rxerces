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

namespace :gem do
  desc "Create the sys-uname gem"
  task :create => [:clean] do
    require 'rubygems/package'
    spec = Gem::Specification.load('rxerces.gemspec')
    spec.signing_key = File.join(Dir.home, '.ssh', 'gem-private_key.pem')
    Gem::Package.build(spec)
  end

  desc "Install the sys-uname gem"
  task :install => [:create] do
    file = Dir["*.gem"].first
    sh "gem install #{file}"
  end
end

Rake::ExtensionTask.new("rxerces") do |ext|
  ext.lib_dir = "lib/rxerces"
end

RSpec::Core::RakeTask.new(:spec) do |t|
  t.verbose = false
  t.rspec_opts = '-f documentation -w'
end

task default: [:compile, :spec]
