# frozen_string_literal: true

require "set"

module RuboCop
  module Cop
    module RSpec
      class UnusedLet < ::RuboCop::Cop::RSpec::Base
        # A mutable record of one example or shared group: the `let`s it defines,
        # the references it makes (kept apart by whether they sit in a helper
        # body or in an example), whether it pulls in a shared example group, and
        # which of its `let`s have been resolved to a reference.
        class Scope
          # @rbs! type kind = :example | :shared

          attr_reader :node #: RuboCop::AST::Node
          attr_reader :kind #: kind
          attr_reader :defs #: Array[[ Symbol, Symbol, RuboCop::AST::Node ]] -- `[helper, name, node]` per `let`
          attr_reader :refs #: Set[Symbol] -- names referenced in this group's helper bodies
          attr_reader :refs_in_example #: Set[Symbol] -- names referenced outside this group's helper bodies
          attr_reader :inclusion #: bool -- whether this group pulls in a shared example group
          attr_reader :resolved #: Set[Symbol] -- names of this group's `let`s resolved to a reference

          # @rbs node: RuboCop::AST::Node
          # @rbs kind: kind
          def initialize(node:, kind:) #: void
            @node = node
            @kind = kind
            @defs = []
            @refs = Set.new
            @refs_in_example = Set.new
            @inclusion = false
            @resolved = Set.new
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

          # @rbs name: Symbol
          def add_reference_in_example(name) #: void
            refs_in_example << name
          end

          def mark_inclusion #: void
            self.inclusion = true
          end

          # @rbs name: Symbol
          def mark_referenced(name) #: void
            resolved << name
          end

          def example? #: bool
            kind == :example
          end

          def defined_names #: Array[Symbol]
            defs.map { |_, name, _| name }
          end

          # Shared groups never report — their `let`s may be consumed by external
          # including groups.
          def unreferenced_defs #: Array[[ Symbol, Symbol, RuboCop::AST::Node ]]
            return [] unless example?

            defs.reject { |_, name, _| resolved.include?(name) }
          end

          private

          attr_writer :inclusion #: bool
        end
      end
    end
  end
end
