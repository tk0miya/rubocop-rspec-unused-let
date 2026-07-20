# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpec
      class UnusedLet < ::RuboCop::Cop::RSpec::Base
        # A mutable snapshot of one example/shared group. {ScopeBuilder}
        # populates a scope with its own definitions and references as the group
        # is entered, and its finished children are folded in via #absorb as they
        # leave the stack. `refs`, `incl`, and `def_counts` therefore grow from "this
        # group only" to "this whole subtree" by the time the group is resolved.
        # Ancestors live on the traversal stack, so #unreferenced_defs receives
        # them explicitly rather than via a pointer.
        class Scope
          # @rbs! type kind = :example | :shared

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

          attr_reader :node #: RuboCop::AST::Node -- the group's block node
          attr_reader :kind #: kind -- :example or :shared
          attr_reader :type #: Symbol? -- `type:` metadata declared on this group
          attr_reader :defs #: Array[[ Symbol, Symbol, RuboCop::AST::Node ]] -- `[helper, name, node]` per `let` here
          attr_reader :def_names #: Set[Symbol] -- names defined directly in this group
          attr_reader :helper_refs #: Set[Symbol] -- names referenced in this group's helper bodies
          attr_reader :refs #: Set[Symbol] -- names referenced anywhere in this subtree
          attr_reader :incl #: bool -- whether a shared inclusion sits anywhere in this subtree
          attr_reader :def_counts #: Hash[Symbol, Integer] -- definition count per name in this subtree

          # @rbs node: RuboCop::AST::Node
          # @rbs kind: kind
          # @rbs type: Symbol?
          def initialize(node:, kind:, type:) #: void
            @node = node
            @kind = kind
            @type = type
            @defs = []
            @def_names = Set.new
            @helper_refs = Set.new
            @refs = Set.new
            @incl = false
            @def_counts = Hash.new(0)
          end

          # @rbs helper: Symbol
          # @rbs name: Symbol
          # @rbs def_node: RuboCop::AST::Node
          def add_definition(helper, name, def_node) #: void
            defs << [helper, name, def_node]
            def_names << name
            def_counts[name] = def_counts.fetch(name, 0) + 1
          end

          # @rbs name: Symbol
          def add_reference(name) #: void
            refs << name
          end

          # A reference here can reach a `let` defined in a *descendant* group,
          # since helper bodies run in the example's scope.
          #
          # @rbs name: Symbol
          def add_helper_reference(name) #: void
            helper_refs << name
          end

          def mark_inclusion #: void
            self.incl = true
          end

          # Fold a finished child's subtree aggregates into this scope.
          #
          # @rbs child: Scope
          def absorb(child) #: void
            refs.merge(child.refs)
            self.incl ||= child.incl
            child.def_counts.each { |name, n| def_counts[name] = def_counts.fetch(name, 0) + n }
          end

          # An example group (`describe`/`context`/...), as opposed to a shared
          # group (`shared_examples`/`shared_context`).
          def example? #: bool
            kind == :example
          end

          # Definitions here that no reference could ever reach, given the
          # enclosing `ancestors` (innermost first). Shared groups never report —
          # their `let`s may be consumed by external including groups.
          #
          # @rbs ancestors: Array[Scope]
          def unreferenced_defs(ancestors) #: Array[[ Symbol, Symbol, RuboCop::AST::Node ]]
            return [] unless example?

            defs.reject { |_, name, _| reachable?(name, ancestors) }
          end

          private

          attr_writer :incl #: bool

          # Could a reference to `name` (defined here) resolve to this
          # definition anywhere it is visible?
          #
          # @rbs name: Symbol
          # @rbs ancestors: Array[Scope]
          def reachable?(name, ancestors) #: bool
            incl ||
              refs.include?(name) ||
              overridden?(name, ancestors) ||
              implicitly_used?(name, ancestors) ||
              ancestors.any? { _1.helper_refs.include?(name) }
          end

          # Part of an override chain: redefined deeper in this subtree, or
          # shadowing an ancestor's definition (either may be reached via `super`).
          #
          # @rbs name: Symbol
          # @rbs ancestors: Array[Scope]
          def overridden?(name, ancestors) #: bool
            def_counts.fetch(name, 0) > 1 ||
              ancestors.any? { _1.def_names.include?(name) }
          end

          # Referenced implicitly by a known gem's shared context, keyed by the
          # `type:` metadata visible here.
          #
          # @rbs name: Symbol
          # @rbs ancestors: Array[Scope]
          def implicitly_used?(name, ancestors) #: bool
            type = effective_type(ancestors)
            return false unless type

            Array(IMPLICIT_LETS_BY_TYPE[type]).include?(name)
          end

          # `type:` metadata visible here, innermost-first so an inner group's
          # `type:` overrides an outer one.
          #
          # @rbs ancestors: Array[Scope]
          def effective_type(ancestors) #: Symbol?
            [self, *ancestors].filter_map(&:type).first
          end
        end
      end
    end
  end
end
