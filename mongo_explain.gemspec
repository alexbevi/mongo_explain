# frozen_string_literal: true

require_relative "lib/mongo_explain/version"

Gem::Specification.new do |spec|
  spec.name = "mongo_explain"
  spec.version = MongoExplain::VERSION
  spec.authors = ["Alex Bevilacqua"]
  spec.email = ["alex@alexbevi.com"]

  spec.summary = "MongoDB explain monitoring with optional Rails UI overlay"
  spec.description = "Standalone MongoDB explain monitor with standard logger output and optional Rails-engine ActionCable overlay."
  spec.homepage = "https://github.com/alexbevi/mongo_explain"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "README.md", "Rakefile", "LICENSE"]
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "mongo", ">= 2.18", "< 3.0"
  spec.add_dependency "bigdecimal"
  spec.add_development_dependency "rspec", ">= 3.13"
end
