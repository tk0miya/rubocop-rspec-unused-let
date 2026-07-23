# frozen_string_literal: true

require_relative "unused_let/matchers"
require_relative "unused_let/references"
require_relative "unused_let/scope"
require_relative "unused_let/scope_builder"
require_relative "unused_let/shared_example_registry"

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
      # * When an example group includes a shared example whose block is defined
      #   in the same file (`it_behaves_like`, `include_examples`,
      #   `include_context`, ...), only the `let`s that block actually references
      #   are treated as used; the rest stay checked.
      # * When the included block is not defined in this file (or is included
      #   under a dynamically computed name), every `let` visible at that
      #   inclusion point is ignored, because the shared block may reference any
      #   of them.
      # * `let` definitions whose name is implicitly consumed by a well-known
      #   gem's shared context (identified by the `type:` metadata on an
      #   example group or one of its ancestors) are ignored. Currently this
      #   covers {https://github.com/izumin5210/rspec-validator_spec_helper
      #   rspec-validator_spec_helper}, whose `type: :validator` groups inject
      #   a shared subject that dereferences `value`, `attribute_names`, and
      #   `options` via `eval`.
      # * Helper specs (rspec-rails `type: :helper` groups, or spec files under
      #   `spec/helpers`) are skipped by default, because the described module
      #   is auto-included into the example group and its (externally defined)
      #   methods may reference any `let` in scope, invisibly to single-file
      #   analysis. Set `CheckHelperSpecs: true` to check them anyway.
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
      # @example CheckHelperSpecs: false (default)
      #   # good - a helper spec's `let`s may be referenced by the auto-included
      #   # module's methods, so they are not flagged
      #   describe MyHelper, type: :helper do
      #     let(:current_user) { User.new }
      #
      #     it { expect(helper.greeting).to eq("Hi") }
      #   end
      #
      # @example CheckHelperSpecs: true
      #   # bad - helper specs are checked like any other group
      #   describe MyHelper, type: :helper do
      #     let(:unused) { 1 }
      #
      #     it { expect(helper.greeting).to eq("Hi") }
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
          @builder = ScopeBuilder.new(
            processed_source.file_path,
            SharedExampleRegistry.new(processed_source.ast)
          )
        end

        # RuboCop visits nested groups on their own `on_block`, so we never
        # descend manually. On the way in the ancestors are exactly the scopes
        # already on the stack, so resolve this group's references against them
        # now; descendant groups resolve against this one later, as they are
        # entered.
        #
        # @rbs node: RuboCop::AST::Node
        def on_block(node) #: void
          return unless builder.spec_group?(node)

          scope = builder.build_from(node)
          mark(scope)
          stack.push(scope)
        end

        # A group's `let`s know whether they were referenced once its whole
        # subtree has been entered, which is complete by the time it is left.
        #
        # A group nested inside a `shared_examples`/`shared_context` block is
        # never reported: its `let`s may be consumed by the (possibly external)
        # groups that include the shared block, exactly like `let`s written
        # directly in the shared block.
        #
        # @rbs node: RuboCop::AST::Node
        def after_block(node) #: void
          return unless builder.spec_group?(node)

          scope = stack.pop
          return unless scope

          report(scope) unless stack.any?(&:shared?)
        end

        private

        attr_reader :stack #: Array[Scope]
        attr_reader :builder #: ScopeBuilder

        # Resolve `scope`'s references against the enclosing groups (the scopes
        # currently on the stack) and mark every definition they reach.
        #
        # @rbs scope: Scope
        def mark(scope) #: void
          ancestors = stack
          mark_upward(scope, ancestors)
          mark_downward(scope, ancestors)
          mark_referenced_all(scope, ancestors) if scope.inclusion
          mark_referenced_all(scope, ancestors) if ignore_helper_spec?(scope, ancestors)
        end

        # A reference made in this group, whether in an example or a helper body,
        # reaches a `let` defined here or in an enclosing group.
        #
        # @rbs scope: Scope
        # @rbs ancestors: Array[Scope]
        def mark_upward(scope, ancestors) #: void
          (scope.refs | scope.refs_in_example).each do |name|
            scope.mark_referenced(name)
            ancestors.each { _1.mark_referenced(name) }
          end
        end

        # A helper body in an enclosing group can reference a `let` defined here,
        # since it runs in the example's scope.
        #
        # @rbs scope: Scope
        # @rbs ancestors: Array[Scope]
        def mark_downward(scope, ancestors) #: void
          scope.defs.each do |_, name, _|
            scope.mark_referenced(name) if ancestors.any? { _1.refs.include?(name) }
          end
        end

        # A helper spec (rspec-rails `type: :helper`, or a `spec/helpers/...`
        # file location) auto-includes the described module into the example
        # group, so any of its externally defined methods may reference any
        # `let` in scope — invisible to single-file analysis. Unless the user
        # opts in via `CheckHelperSpecs`, treat every definition in scope as
        # referenced. This judgement is independent of shared inclusions.
        #
        # @rbs scope: Scope
        # @rbs ancestors: Array[Scope]
        def ignore_helper_spec?(scope, ancestors) #: bool
          return false if cop_config["CheckHelperSpecs"]

          helper_spec?(scope, ancestors)
        end

        # The effective `type:` is the innermost one in the group's ancestry
        # (each scope already carries its explicit type, or `:helper` inferred
        # from a `spec/helpers` location).
        #
        # @rbs scope: Scope
        # @rbs ancestors: Array[Scope]
        def helper_spec?(scope, ancestors) #: bool
          [scope, *ancestors].filter_map(&:type).first == :helper
        end

        # Treat every `let` visible in `scope` (its own and its ancestors') as
        # referenced. Used where references can't be fully seen from this file:
        # a shared inclusion, or a helper spec's auto-included module.
        #
        # @rbs scope: Scope
        # @rbs ancestors: Array[Scope]
        def mark_referenced_all(scope, ancestors) #: void
          [scope, *ancestors].each do |group|
            group.defined_names.each { group.mark_referenced(_1) }
          end
        end

        # @rbs scope: Scope
        def report(scope) #: void
          scope.unreferenced_defs.each do |helper, name, let_node|
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
