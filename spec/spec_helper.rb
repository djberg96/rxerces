require 'rspec'
require 'rxerces'
require 'rxerces_shared'
require 'mkmf-lite'

RSpec.configure do |config|
  include Mkmf::Lite

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include_context(RXerces)

  config.filter_run_excluding(:xalan) unless have_library('xalan-c')
end
