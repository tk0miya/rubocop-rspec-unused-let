# frozen_string_literal: true

# Helpers for unit specs of the UnusedLet support classes, which operate on
# raw AST nodes outside of a cop investigation.
module UnusedLetAstHelper
  # Parse `source` and return the root node.
  def parse(source)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f)
    raise ArgumentError, "invalid source: #{processed.diagnostics.map(&:render)}" unless processed.valid_syntax?

    processed.ast
  end

  # The example group block node introduced with the given description
  # string, e.g. `group_named(root, "target")` finds `context "target" do`.
  def group_named(root, description)
    found = [root, *root.each_descendant(:block)].find do |node|
      first_argument = node.send_node.first_argument
      first_argument&.str_type? && first_argument.value == description
    end
    found || raise(ArgumentError, "no group named #{description.inspect}")
  end
end

# Everything a unit spec of the support classes needs: the AST helpers above,
# plus the RSpec DSL vocabulary (`describe`, `let`, ...) they resolve through
# `RuboCop::RSpec::Language.config`. During a real run the cop's
# `on_new_investigation` assigns that config; these unit specs assign it
# explicitly so they do not depend on a cop spec having run first, and
# restore the previous value afterwards so no state leaks into other specs.
RSpec.shared_context "with UnusedLet AST helpers" do
  include UnusedLetAstHelper

  around do |example|
    original = RuboCop::RSpec::Language.config
    RuboCop::RSpec::Language.config =
      RuboCop::ConfigLoader.default_configuration["RSpec"]["Language"]
    example.run
  ensure
    RuboCop::RSpec::Language.config = original
  end
end
