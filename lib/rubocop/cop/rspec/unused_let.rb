# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpec
      # Checks for `let` definitions that are never referenced.
      #
      # A `let` (or `let!`) whose name is never used within its scope is dead
      # code that makes specs harder to read. This cop flags such definitions.
      #
      # `let!` is checked as well by default. Since it is sometimes used purely
      # for its side effects (e.g. `let!(:user) { create(:user) }`), you can opt
      # out with `CheckLetBang: false`.
      #
      # To avoid false positives, the cop deliberately stays silent whenever it
      # cannot see every possible reference:
      #
      # * `let` definitions inside a `shared_examples`/`shared_context` block are
      #   ignored, because their consumers live in the (possibly external)
      #   including example groups.
      # * When an example group's subtree contains a shared example inclusion
      #   (`it_behaves_like`, `include_examples`, `include_context`, ...), the
      #   `let` definitions visible at that inclusion point are ignored, because
      #   the (possibly external) shared block may reference them.
      # * `let` definitions that participate in an override chain (redefined in a
      #   nested group, or overriding an outer definition) are ignored, since the
      #   outer definition may be reached through `super`.
      #
      # Dynamic references such as `send(:foo)` are treated as usages.
      #
      # @example
      #   # bad
      #   describe Foo do
      #     let(:used) { 1 }
      #     let(:unused) { 2 }
      #
      #     it { expect(used).to eq(1) }
      #   end
      #
      #   # good
      #   describe Foo do
      #     let(:used) { 1 }
      #
      #     it { expect(used).to eq(1) }
      #   end
      #
      # @example CheckLetBang: true (default)
      #   # bad
      #   describe Foo do
      #     let!(:widget) { create(:widget) }
      #
      #     it { expect(Widget.count).to eq(1) }
      #   end
      #
      # @example CheckLetBang: false
      #   # good - `let!` is assumed to be used for its side effects
      #   describe Foo do
      #     let!(:widget) { create(:widget) }
      #
      #     it { expect(Widget.count).to eq(1) }
      #   end
      #
      # @safety
      #   Autocorrect deletes the flagged `let` definition. That is behaviorally
      #   safe for a plain `let`, whose block never runs when the helper is
      #   unreferenced, but a `let!` block is executed eagerly and may exist
      #   purely for its side effects. RuboCop treats autocorrect safety as a
      #   whole-cop setting, so the cop is marked unsafe and both `let` and
      #   `let!` are only removed under `rubocop --autocorrect-all`.
      class UnusedLet < ::RuboCop::Cop::RSpec::Base
        extend AutoCorrector

        include RangeHelp

        MSG = "`%<helper>s(:%<name>s)` is not referenced anywhere. " \
              "Remove it or reference it in an example."

        DYNAMIC_DISPATCH_METHODS = %i[
          send public_send __send__ method respond_to?
        ].freeze

        # Signatures for the helpers defined dynamically by the node pattern
        # macros below (rbs-inline cannot infer these).
        #
        # @rbs!
        #   def example_group?: (RuboCop::AST::Node node) -> bool
        #   def spec_group?: (RuboCop::AST::Node node) -> bool
        #   def let_definition: (RuboCop::AST::Node node) -> [ Symbol, (Symbol | String) ]?
        #   def method_called?: (RuboCop::AST::Node node, Symbol name) -> bool
        #   def contains_inclusion?: (RuboCop::AST::Node node) -> bool

        def_node_matcher :example_group?, <<~PATTERN
          (block (send #rspec? #ExampleGroups.all ...) ...)
        PATTERN

        def_node_matcher :spec_group?, <<~PATTERN
          (block (send #rspec? {#ExampleGroups.all #SharedGroups.all} ...) ...)
        PATTERN

        def_node_matcher :let_definition, <<~PATTERN
          {
            (block (send nil? ${:let :let!} ({sym str} $_) ...) ...)
            (send nil? ${:let :let!} ({sym str} $_) block_pass)
          }
        PATTERN

        def_node_search :method_called?, "(send nil? %)"

        def_node_search :contains_inclusion?, "(send nil? #Includes.all ...)"

        # @rbs node: RuboCop::AST::Node
        def on_block(node) #: void
          return unless example_group?(node)
          # A shared example inclusion anywhere in this group's subtree can
          # consume any `let` visible here, so we cannot judge them.
          return if contains_inclusion?(node)

          RuboCop::RSpec::ExampleGroup.new(node).lets.each do |let|
            check_let(node, let)
          end
        end

        private

        # @rbs group: RuboCop::AST::Node
        # @rbs let: RuboCop::AST::Node
        def check_let(group, let) #: void
          helper, name = let_definition(let)
          return unless name
          return if helper == :let! && !cop_config["CheckLetBang"]
          return if override_chain?(group, name)
          return if referenced?(group, name)

          node = let #: untyped
          send_node = node.block_type? ? node.send_node : node
          add_offense(send_node, message: format(MSG, helper: helper, name: name)) do |corrector|
            corrector.remove(
              range_by_whole_lines(node.source_range, include_final_newline: true)
            )
          end
        end

        # @rbs group: RuboCop::AST::Node
        # @rbs name: Symbol | String
        def referenced?(group, name) #: bool
          method_called?(group, name.to_sym) ||
            dynamically_referenced?(group, name)
        end

        # @rbs group: RuboCop::AST::Node
        # @rbs name: Symbol | String
        def dynamically_referenced?(group, name) #: bool
          target = name.to_s
          group.each_descendant(:send).any? do |send_node|
            node = send_node #: untyped
            next false unless DYNAMIC_DISPATCH_METHODS.include?(node.method_name)

            arg = node.first_argument
            arg&.type?(:sym, :str) && arg.value.to_s == target
          end
        end

        # @rbs group: RuboCop::AST::Node
        # @rbs name: Symbol | String
        def override_chain?(group, name) #: bool
          overrides_outer?(group, name) ||
            redefined_in_descendant?(group, name)
        end

        # @rbs group: RuboCop::AST::Node
        # @rbs name: Symbol | String
        def overrides_outer?(group, name) #: bool
          group.each_ancestor(:block).any? do |ancestor|
            next false unless spec_group?(ancestor)

            RuboCop::RSpec::ExampleGroup.new(ancestor).lets.any? do |let|
              _, other = let_definition(let)
              other == name
            end
          end
        end

        # @rbs group: RuboCop::AST::Node
        # @rbs name: Symbol | String
        def redefined_in_descendant?(group, name) #: bool
          count = 0
          group.each_descendant(:block, :send) do |descendant|
            _, other = let_definition(descendant)
            count += 1 if other == name
            return true if count > 1
          end
          false
        end
      end
    end
  end
end
