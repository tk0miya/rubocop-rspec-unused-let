# frozen_string_literal: true

require "lint_roller"

module Rubocop
  module Rspec
    module Unused
      module Let
        # A RuboCop plugin (LintRoller) that registers this gem's cops and
        # default configuration. Referenced from the gemspec via the
        # `default_lint_roller_plugin` metadata, so users can enable it with:
        #
        #   plugins:
        #     - rubocop-rspec
        #     - rubocop-rspec-unused-let
        class Plugin < LintRoller::Plugin
          # @rbs override
          def about
            LintRoller::About.new(
              name: "rubocop-rspec-unused-let",
              version: VERSION,
              homepage: "https://github.com/tk0miya/rubocop-rspec-unused-let",
              description: "Detects unreferenced RSpec `let` definitions."
            )
          end

          # @rbs override
          def supported?(context)
            context.engine == :rubocop
          end

          # @rbs override
          def rules(_context)
            LintRoller::Rules.new(
              type: :path,
              config_format: :rubocop,
              value: CONFIG_DEFAULT
            )
          end
        end
      end
    end
  end
end
