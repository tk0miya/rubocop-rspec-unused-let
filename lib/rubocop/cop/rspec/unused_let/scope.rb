# frozen_string_literal: true

require "set"

module RuboCop
  module Cop
    module RSpec
      class UnusedLet < ::RuboCop::Cop::RSpec::Base
        # A mutable snapshot of one example/shared group. {ScopeBuilder}
        # populates a scope with its own definitions and references as the group
        # is entered, and its finished children are folded in via #absorb as they
        # leave the stack. `refs` and `inclusion` therefore grow from "this
        # group only" to "this whole subtree" by the time the group is resolved.
        # Ancestors live on the traversal stack, so #unreferenced_defs receives
        # them explicitly rather than via a pointer.
        class Scope
          # @rbs! type kind = :example | :shared

          attr_reader :node #: RuboCop::AST::Node -- the group's block node
          attr_reader :kind #: kind -- :example or :shared
          attr_reader :defs #: Array[[ Symbol, Symbol, RuboCop::AST::Node ]] -- `[helper, name, node]` per `let` here
          attr_reader :helper_refs #: Set[Symbol] -- names referenced in this group's helper bodies
          attr_reader :refs #: Set[Symbol] -- names referenced anywhere in this subtree
          attr_reader :inclusion #: bool -- whether a shared inclusion sits anywhere in this subtree

          # @rbs node: RuboCop::AST::Node
          # @rbs kind: kind
          def initialize(node:, kind:) #: void
            @node = node
            @kind = kind
            @defs = []
            @helper_refs = Set.new
            @refs = Set.new
            @inclusion = false
          end

          # @rbs helper: Symbol
          # @rbs name: Symbol
          # @rbs def_node: RuboCop::AST::Node
          def add_definition(helper, name, def_node) #: void
            defs << [helper, name, def_node]
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
            self.inclusion = true
          end

          # Fold a finished child's subtree aggregates into this scope.
          #
          # @rbs child: Scope
          def absorb(child) #: void
            refs.merge(child.refs)
            self.inclusion ||= child.inclusion
          end

          # An example group (`describe`/`context`/...), as opposed to a shared
          # group (`shared_examples`/`shared_context`).
          def example? #: bool
            kind == :example
          end

          # Definitions here whose name is never referenced within this group's
          # subtree, given the enclosing `ancestors` (innermost first). Shared
          # groups never report — their `let`s may be consumed by external
          # including groups.
          #
          # @rbs ancestors: Array[Scope]
          def unreferenced_defs(ancestors) #: Array[[ Symbol, Symbol, RuboCop::AST::Node ]]
            return [] unless example?

            defs.reject { |_, name, _| reachable?(name, ancestors) }
          end

          private

          attr_writer :inclusion #: bool

          # Could a reference reach the definition of `name` in this group? `refs`
          # spans the whole subtree, so a reference in this group or any nested
          # group counts, as does a reference in an ancestor helper body (which
          # runs in the example's scope and so resolves to this definition).
          #
          # @rbs name: Symbol
          # @rbs ancestors: Array[Scope]
          def reachable?(name, ancestors) #: bool
            inclusion ||
              refs.include?(name) ||
              ancestors.any? { _1.helper_refs.include?(name) }
          end
        end
      end
    end
  end
end
