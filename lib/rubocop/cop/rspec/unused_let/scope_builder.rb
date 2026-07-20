# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpec
      class UnusedLet < ::RuboCop::Cop::RSpec::Base
        # Turns an example/shared group AST node into a {Scope}, collecting the
        # group's own definitions and references (but not those of nested groups,
        # which become their own scopes). This is the only part of the cop that
        # needs RSpec's node-pattern matchers, so it is kept out of both the cop
        # (RuboCop lifecycle) and {Scope} (pure data and queries).
        class ScopeBuilder
          include ::RuboCop::RSpec::Language
          extend ::RuboCop::AST::NodePattern::Macros

          DYNAMIC_DISPATCH_METHODS = %i[
            send public_send __send__ method respond_to?
          ].freeze

          # `let` names that well-known gems' shared contexts implicitly
          # reference, hidden from single-file analysis, keyed by the `type:`
          # metadata that pulls the shared context in. When a group carries a
          # matching `type:`, the listed names are recorded as references so
          # that `let`s of those names (here or in a descendant) count as used.
          IMPLICIT_REFS_BY_TYPE = {
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

          # Signatures for the node-pattern matchers defined below (rbs-inline
          # cannot infer these).
          #
          # @rbs!
          #   def example_group?: (RuboCop::AST::Node node) -> bool
          #   def spec_group?: (RuboCop::AST::Node node) -> bool
          #   def let_definition: (RuboCop::AST::Node node) -> [ Symbol, (Symbol | String) ]?
          #   def inclusion_call?: (RuboCop::AST::Node node) -> bool

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

          def_node_matcher :inclusion_call?, "(send nil? #Includes.all ...)"

          # Build the Scope for `node` from its own region alone; nested groups
          # are left for their own traversal and folded in later via Scope#absorb.
          #
          # @rbs node: RuboCop::AST::Node
          def build_from(node) #: Scope
            kind = example_group?(node) ? :example : :shared #: Scope::kind
            scope = Scope.new(node: node, kind: kind)
            collect_definitions(node, scope)
            collect_region_references(node, scope)
            collect_helper_references(node, scope)
            inject_implicit_references(node, scope)
            scope
          end

          private

          # A well-known gem's shared context (pulled in by `type:` metadata)
          # can reference `let` names that single-file analysis never sees.
          # Record them exactly as a real helper on this group would be: a real
          # reference lands in both sets, so mirror that. `refs` justifies a
          # `let` defined here (or, via #absorb, in an ancestor group), while
          # `helper_refs` reaches `let`s in descendant groups, since helper
          # bodies run in the example's scope.
          #
          # @rbs node: RuboCop::AST::Node
          # @rbs scope: Scope
          def inject_implicit_references(node, scope) #: void
            type = type_from_group(node)
            names = type && IMPLICIT_REFS_BY_TYPE[type]
            return unless names

            names.each do |name|
              scope.add_reference(name)
              scope.add_helper_reference(name)
            end
          end

          # @rbs node: RuboCop::AST::Node
          # @rbs scope: Scope
          def collect_definitions(node, scope) #: void
            RuboCop::RSpec::ExampleGroup.new(node).lets.each do |let|
              helper, name = let_definition(let)
              scope.add_definition(helper, name.to_sym, let) if helper && name
            end
          end

          # References and inclusions in `node`'s own region, stopping at nested
          # spec groups (each handled by its own build).
          #
          # @rbs node: RuboCop::AST::Node
          # @rbs scope: Scope
          def collect_region_references(node, scope) #: void
            node.each_child_node do |child|
              next if spec_group?(child)

              references_in(child).each { scope.add_reference(_1) }
              scope.mark_inclusion if inclusion_call?(child)
              collect_region_references(child, scope)
            end
          end

          # References inside the group's own `let`/`subject`/hook/`def` bodies.
          #
          # @rbs node: RuboCop::AST::Node
          # @rbs scope: Scope
          def collect_helper_references(node, scope) #: void
            group = RuboCop::RSpec::ExampleGroup.new(node)
            helpers = group.lets +
                      group.subjects +
                      group.hooks.map(&:to_node) +
                      method_definitions_in(node)

            helpers.each { record_helper_references(_1, scope) }
          end

          # @rbs node: RuboCop::AST::Node
          # @rbs scope: Scope
          def record_helper_references(node, scope) #: void
            references_in(node).each { scope.add_helper_reference(_1) }
            node.each_child_node { record_helper_references(_1, scope) }
          end

          # `let`-visible names a single send node references: a bare (nil
          # receiver) call, plus any dynamic-dispatch target such as `send(:foo)`.
          #
          # @rbs node: RuboCop::AST::Node
          def references_in(node) #: Array[Symbol]
            return [] unless node.send_type?

            send = node #: untyped
            names = [] #: Array[Symbol]
            names << send.method_name if send.receiver.nil?
            if DYNAMIC_DISPATCH_METHODS.include?(send.method_name)
              arg = send.first_argument
              names << arg.value.to_sym if arg&.type?(:sym, :str)
            end
            names
          end

          # `def foo` written at an example group's level becomes an instance
          # method on the group's example class. Skip `def`s nested inside a
          # deeper example/shared group — those aren't visible from `node`.
          #
          # @rbs node: RuboCop::AST::Node
          def method_definitions_in(node) #: Array[RuboCop::AST::Node]
            node.each_descendant(:def).select do |defn|
              inner = defn #: untyped
              nearest = inner.each_ancestor(:block).find do |b|
                b.equal?(node) || spec_group?(b)
              end
              nearest.equal?(node)
            end
          end

          # @rbs node: RuboCop::AST::Node
          def type_from_group(node) #: Symbol?
            block = node #: untyped
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
        end
      end
    end
  end
end
