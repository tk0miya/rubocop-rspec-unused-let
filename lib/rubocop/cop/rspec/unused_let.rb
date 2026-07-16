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

        DYNAMIC_DISPATCH_METHODS = %i[
          send public_send __send__ method respond_to?
        ].freeze

        # Well-known gems whose shared contexts inject `let` definitions that
        # single-file analysis cannot see referenced, keyed by the `type:`
        # metadata that pulls the shared context in. When an example group
        # (or any of its ancestors) carries a matching `type:`, the listed
        # `let` names are treated as referenced.
        IMPLICIT_LETS_BY_TYPE = {
          # rspec-validator_spec_helper
          # https://github.com/izumin5210/rspec-validator_spec_helper
          # `type: :validator` triggers a shared subject that dereferences
          # these names via `eval`, hidden from static analysis.
          validator: %i[
            value attribute_names options
            validator_name validator_class validator_type validation_name
            model_class
          ].freeze
        }.freeze

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

          used_names = used_let_names(node)
          RuboCop::RSpec::ExampleGroup.new(node).lets.each do |let|
            check_let(node, let, used_names)
          end
        end

        private

        # @rbs group: RuboCop::AST::Node
        # @rbs let: RuboCop::AST::Node
        # @rbs used_names: Array[Symbol]
        def check_let(group, let, used_names) #: void # rubocop:disable Metrics/CyclomaticComplexity
          helper, name = let_definition(let)
          return unless name
          return if helper == :let! && !cop_config["CheckLetBang"]
          return if used_names.include?(name.to_sym)
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

        # `let` names that a known gem's shared context references
        # implicitly (and therefore should be treated as used) given the
        # `type:` metadata visible at `group` or on any of its ancestor
        # example groups. Empty array when no matching known-gem pattern
        # applies.
        #
        # @rbs group: RuboCop::AST::Node
        def used_let_names(group) #: Array[Symbol]
          Array(IMPLICIT_LETS_BY_TYPE[effective_type(group)])
        end

        # `type:` metadata visible at `group`, walking innermost-first so an
        # inner group's `type:` overrides an outer one — matching RSpec's
        # own metadata cascade.
        #
        # @rbs group: RuboCop::AST::Node
        def effective_type(group) #: Symbol?
          [group, *group.each_ancestor(:block)].each do |ancestor|
            next unless spec_group?(ancestor)

            type = type_from_group(ancestor)
            return type if type
          end
          nil
        end

        # @rbs spec_group: RuboCop::AST::Node
        def type_from_group(spec_group) #: Symbol?
          block = spec_group #: untyped
          block.send_node.arguments.each do |arg|
            next unless arg.hash_type?

            arg.pairs.each do |pair|
              key = pair.key
              value = pair.value
              return value.value if key.sym_type? && key.value == :type && value.sym_type?
            end
          end
          nil
        end

        # @rbs group: RuboCop::AST::Node
        # @rbs name: Symbol | String
        def referenced?(group, name) #: bool
          method_called?(group, name.to_sym) ||
            dynamically_referenced?(group, name) ||
            referenced_in_ancestor_scope?(group, name)
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

        # `let`, `subject`, and hook blocks — and plain `def` helpers — defined
        # in ancestor groups are evaluated in the example's scope, so a
        # reference to `name` there resolves to the definition visible at the
        # running example.
        #
        # @rbs group: RuboCop::AST::Node
        # @rbs name: Symbol | String
        def referenced_in_ancestor_scope?(group, name) #: bool
          ancestor_scope_nodes(group).any? do |scope_node|
            method_called?(scope_node, name.to_sym) ||
              dynamically_referenced?(scope_node, name)
          end
        end

        # @rbs group: RuboCop::AST::Node
        def ancestor_scope_nodes(group) #: Array[RuboCop::AST::Node]
          group.each_ancestor(:block).flat_map do |ancestor|
            next [] unless spec_group?(ancestor)

            ancestor_group = RuboCop::RSpec::ExampleGroup.new(ancestor)
            ancestor_group.lets +
              ancestor_group.subjects +
              ancestor_group.hooks.map(&:to_node) +
              method_definitions_in(ancestor)
          end
        end

        # `def foo` written at an example group's level becomes an instance
        # method on the group's example class, so calls to a `let` from inside
        # such a helper count as references. Skip `def`s nested inside a
        # deeper example/shared group — those aren't visible from `ancestor`.
        #
        # @rbs ancestor: RuboCop::AST::Node
        def method_definitions_in(ancestor) #: Array[RuboCop::AST::Node]
          ancestor.each_descendant(:def).select do |defn|
            node = defn #: untyped
            nearest = node.each_ancestor(:block).find do |b|
              b.equal?(ancestor) || spec_group?(b)
            end
            nearest.equal?(ancestor)
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
