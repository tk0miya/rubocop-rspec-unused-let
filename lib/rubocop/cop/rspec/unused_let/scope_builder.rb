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
          include ReferenceScanner
          extend ::RuboCop::AST::NodePattern::Macros

          # Inclusions that evaluate the shared block in a freshly created
          # nested example group, which cannot see the host group's descendants.
          # Every other inclusion (`include_context`, `include_examples`, and
          # unknown aliases) is assumed to splice hooks and helpers into the host
          # group, where descendant examples inherit them.
          NESTED_GROUP_INCLUDES = %i[it_behaves_like it_should_behave_like].freeze

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

          # @rbs @resolver: SharedExampleResolver?

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

          # @rbs resolver: SharedExampleResolver?
          def initialize(resolver = nil) #: void
            @resolver = resolver
          end

          # Build the Scope for `node` from its own region alone; nested groups
          # are left for their own traversal.
          #
          # @rbs node: RuboCop::AST::Node
          def build_from(node) #: Scope
            kind = example_group?(node) ? :example : :shared #: Scope::kind
            scope = Scope.new(node: node, kind: kind)
            helpers = helper_nodes(node)
            collect_definitions(node, scope)
            helpers.each { record_helper_references(_1, scope) }
            inclusions = [] #: Array[RuboCop::AST::Node]
            collect_example_references(node, scope, helpers, inclusions)
            inject_implicit_references(node, scope)
            apply_inclusions(scope, inclusions)
            scope
          end

          private

          # Resolve each shared inclusion in the region and record the names its
          # shared block references, so `let`s the shared block never touches
          # stay checkable. If any inclusion cannot be resolved, fall back to
          # marking the group as including a shared example, which silences every
          # `let` visible at the inclusion point.
          #
          # @rbs scope: Scope
          # @rbs inclusions: Array[RuboCop::AST::Node]
          def apply_inclusions(scope, inclusions) #: void
            return if inclusions.empty?

            resolved = resolve_inclusions(inclusions)
            if resolved
              resolved.each { |inclusion, names| inject_shared_references(scope, inclusion, names) }
            else
              scope.mark_inclusion
            end
          end

          # `[inclusion, names]` for every inclusion, or `nil` if any inclusion
          # (or the resolver) could not resolve.
          #
          # @rbs inclusions: Array[RuboCop::AST::Node]
          def resolve_inclusions(inclusions) #: Array[[ RuboCop::AST::Node, Set[Symbol] ]]?
            return nil unless @resolver

            resolver = @resolver #: SharedExampleResolver
            inclusions.map do |inclusion|
              names = resolver.referenced_names(inclusion)
              return nil unless names

              [inclusion, names]
            end
          end

          # A reference in the shared block reaches a `let` here or in an
          # ancestor (`refs_in_example`). Unless the block runs in its own nested
          # group (`it_behaves_like`), it also reaches `let`s in descendant
          # groups (`refs`), since its hooks run in the example's scope.
          #
          # @rbs scope: Scope
          # @rbs inclusion: RuboCop::AST::Node
          # @rbs names: Set[Symbol]
          def inject_shared_references(scope, inclusion, names) #: void
            node = inclusion #: untyped
            nested_group = NESTED_GROUP_INCLUDES.include?(node.method_name)
            names.each do |name|
              scope.add_reference_in_example(name)
              scope.add_reference(name) unless nested_group
            end
          end

          # A well-known gem's shared context (pulled in by `type:` metadata)
          # can reference `let` names that single-file analysis never sees.
          # Record them exactly as a real helper on this group would be: an
          # example reference (justifying a `let` here or in an ancestor) *and* a
          # helper reference (reaching `let`s in descendant groups, since helper
          # bodies run in the example's scope).
          #
          # @rbs node: RuboCop::AST::Node
          # @rbs scope: Scope
          def inject_implicit_references(node, scope) #: void
            type = type_from_group(node)
            names = type && IMPLICIT_REFS_BY_TYPE[type]
            return unless names

            names.each do |name|
              scope.add_reference_in_example(name)
              scope.add_reference(name)
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

          # References in `node`'s region that sit *outside* its helper bodies
          # (examples and any other group-level code), collected into
          # `refs_in_example`. Stops at nested spec groups and skips the helper
          # definitions, whose references belong to `refs`. Collects the shared
          # inclusion calls found along the way into `inclusions`.
          #
          # @rbs node: RuboCop::AST::Node
          # @rbs scope: Scope
          # @rbs helpers: Array[RuboCop::AST::Node]
          # @rbs inclusions: Array[RuboCop::AST::Node]
          def collect_example_references(node, scope, helpers, inclusions) #: void
            node.each_child_node do |child|
              next if spec_group?(child) || helpers.any? { _1.equal?(child) }

              references_in(child).each { scope.add_reference_in_example(_1) }
              inclusions << child if inclusion_call?(child)
              collect_example_references(child, scope, helpers, inclusions)
            end
          end

          # The group's own `let`/`subject`/hook/`def` definitions, whose bodies
          # run in the example's scope.
          #
          # @rbs node: RuboCop::AST::Node
          def helper_nodes(node) #: Array[RuboCop::AST::Node]
            group = RuboCop::RSpec::ExampleGroup.new(node)
            group.lets +
              group.subjects +
              group.hooks.map(&:to_node) +
              method_definitions_in(node)
          end

          # @rbs node: RuboCop::AST::Node
          # @rbs scope: Scope
          def record_helper_references(node, scope) #: void
            references_in(node).each { scope.add_reference(_1) }
            node.each_child_node { record_helper_references(_1, scope) }
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
