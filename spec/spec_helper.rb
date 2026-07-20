# frozen_string_literal: true

require "rubocop"
require "rubocop-rspec"
require "rubocop/rspec/support"
require "rubocop/rspec/shared_contexts/default_rspec_language_config_context"

require "rubocop/rspec/unused/let"

require_relative "support/unused_let_ast"

# RuboCop only injects rubocop-rspec's default configuration (which provides
# `RSpec/Language`, `RSpec/Include`, etc.) when RuboCop runs with
# `plugins: rubocop-rspec`. The test suite loads it manually so that node
# pattern helpers such as `#ExampleGroups.all` resolve and the
# `with default RSpec/Language config` shared context works.
#
# Our own cop's defaults do not need injecting here: each cop spec sets
# `cop_config` explicitly, so the cop never relies on `config/default.yml`.
RuboCop::ConfigLoader.inject_defaults!(
  Pathname.new(Gem.loaded_specs["rubocop-rspec"].gem_dir).join("config", "default.yml").to_s
)

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
