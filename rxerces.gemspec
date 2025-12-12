Gem::Specification.new do |spec|
  spec.name          = "rxerces"
  spec.version       = "0.1.0"
  spec.authors       = ["RXerces Contributors"]
  spec.email         = ["contributors@example.com"]

  spec.summary       = "Nokogiri-compatible XML library using Xerces-C"
  spec.description   = "A Ruby XML library with Nokogiri-compatible API, powered by Xerces-C instead of libxml2"
  spec.homepage      = "https://github.com/example/rxerces"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 2.7.0"

  spec.files = Dir["lib/**/*", "ext/**/*", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/rxerces/extconf.rb"]

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rake-compiler", "~> 1.2"
  spec.add_development_dependency "rspec", "~> 3.12"
end
