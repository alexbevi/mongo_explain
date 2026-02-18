# frozen_string_literal: true

require_relative "lib/mongo_explain/version"

Gem::Specification.new do |spec|
  spec.name = "mongo_explain"
  spec.version = MongoExplain::VERSION
  spec.authors = ["Hockey Team Budget"]
  spec.email = ["devnull@example.com"]

  spec.summary = "MongoDB explain monitoring and in-app development overlay for Rails"
  spec.description = "Standalone Rails engine for MongoDB explain logging and a realtime ActionCable UI overlay."
  spec.homepage = "https://example.com/mongo_explain"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "README.md", "Rakefile"]
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "mongoid", ">= 9.0"
  spec.add_dependency "rails", ">= 8.0"
end
