# frozen_string_literal: true

require_relative "lib/refactor/version"

Gem::Specification.new do |spec|
  spec.name = "refactor"
  spec.version = Refactor::VERSION
  spec.authors = ["Brandon Weaver"]
  spec.email = ["keystonelemur@gmail.com"]

  spec.summary = "Ruby refactoring tool"
  spec.description = "AST-based Ruby refactoring toolkit"
  spec.homepage = "https://www.github.com/baweaver/refactor"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Consider removing this later and having a more minimal subset
  spec.add_dependency "rubocop"

  spec.add_development_dependency "guard-rspec"
end
