Gem::Specification.new do |spec|
  spec.name        = "rxerces"
  spec.version     = "0.7.0"
  spec.author      = "Daniel J. Berger"
  spec.email       = "djberg96@gmail.com"
  spec.cert_chain  = ["certs/djberg96_pub.pem"]
  spec.homepage    = "http://github.com/djberg96/rxerces"
  spec.summary     = "Nokogiri-compatible XML library using Xerces-C"
  spec.license     = "MIT"
  spec.files       = Dir['**/*'].reject{ |f| f.include?('git') }
  spec.test_files  = Dir['spec/*_spec.rb']
  spec.extensions  = ["ext/rxerces/extconf.rb"]

  spec.required_ruby_version = ">= 2.7.0"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rake-compiler", "~> 1.2"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "mkmf-lite", "~> 0.7.5"

  spec.description = <<-EOF
    A Ruby XML library with Nokogiri-compatible API, powered by Xerces-C
    instead of libxml2. It also optionally uses Xalan for Xpath 1.0 compliance.
  EOF

  spec.metadata = {
    'homepage_uri'          => 'https://github.com/djberg96/rxerces',
    'bug_tracker_uri'       => 'https://github.com/djberg96/rxerces/issues',
    'changelog_uri'         => 'https://github.com/djberg96/rxerces/blob/main/CHANGES.md',
    'documentation_uri'     => 'https://github.com/djberg96/rxerces/wiki',
    'source_code_uri'       => 'https://github.com/djberg96/rxerces',
    'wiki_uri'              => 'https://github.com/djberg96/rxerces/wiki',
    'rubygems_mfa_required' => 'true',
    'github_repo'           => 'https://github.com/djberg96/rxerces',
    'funding_uri'           => 'https://github.com/sponsors/djberg96'
  }
end
