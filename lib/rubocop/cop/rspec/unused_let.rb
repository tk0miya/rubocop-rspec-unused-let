# frozen_string_literal: true

require_relative "unused_let/scope"
require_relative "unused_let/scope_builder"

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
      # * `let` definitions whose name is implicitly consumed by a well-known
      #   gem's shared context (identified by the `type:` metadata on an
      #   example group or one of its ancestors) are ignored. Currently this
      #   covers {https://github.com/izumin5210/rspec-validator_spec_helper
      #   rspec-validator_spec_helper}, whose `type: :validator` groups inject
      #   a shared subject that dereferences `value`, `attribute_names`, and
      #   `options` via `eval`.
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

        def on_new_investigation #: void
          super
          @stack = []
          @builder = ScopeBuilder.new
        end

        # RuboCop visits nested groups on their own `on_block`, so we never
        # descend manually.
        #
        # @rbs node: RuboCop::AST::Node
        def on_block(node) #: void
          stack.push(builder.build_from(node)) if builder.spec_group?(node)
        end

        # A group's subtree is complete by the time it is left, so resolve it
        # here against the ancestors still on the stack, then fold it into its
        # parent.
        #
        # @rbs node: RuboCop::AST::Node
        def after_block(node) #: void
          return unless builder.spec_group?(node)

          scope = stack.pop
          return unless scope

          # `stack` is outermost-first (pushed pre-order); resolution wants the
          # ancestor chain innermost-first.
          resolve(scope, stack.reverse)
          stack.last&.absorb(scope)
        end

        private

        attr_reader :stack #: Array[Scope]
        attr_reader :builder #: ScopeBuilder

        # @rbs scope: Scope
        # @rbs ancestors: Array[Scope]
        def resolve(scope, ancestors) #: void
          scope.unreferenced_defs(ancestors).each do |helper, name, let_node|
            next if helper == :let! && !cop_config["CheckLetBang"]

            add_offense_for(let_node, helper, name)
          end
        end

        # @rbs let_node: RuboCop::AST::Node
        # @rbs helper: Symbol
        # @rbs name: Symbol
        def add_offense_for(let_node, helper, name) #: void
          node = let_node #: untyped
          send_node = node.block_type? ? node.send_node : node
          add_offense(send_node, message: format(MSG, helper: helper, name: name)) do |corrector|
            corrector.remove(
              range_by_whole_lines(node.source_range, include_final_newline: true)
            )
          end
        end
      end
    end
  end
end
