# frozen_string_literal: true

require "set"

module RuboCop
  module Cop
    module RSpec
      class UnusedLet < ::RuboCop::Cop::RSpec::Base
        # A mutable record of one example or shared group: the `let`s it defines,
        # the references it makes (kept apart by whether they sit in a helper
        # body or in an example), whether an example runs in it, whether it pulls
        # in a shared example group, and which of its `let`s have been resolved
        # to a reference.
        class Scope
          # @rbs! type kind = :example | :shared

          attr_reader :node #: RuboCop::AST::Node
          attr_reader :kind #: kind
          attr_reader :defs #: Array[[ Symbol, Symbol, RuboCop::AST::Node ]] -- `[helper, name, node]` per `let`
          attr_reader :refs #: Set[Symbol] -- names referenced in this group's helper bodies
          attr_reader :refs_in_example #: Set[Symbol] -- names referenced outside this group's helper bodies
          attr_reader :inclusion #: bool -- whether this group pulls in a shared example group
          attr_reader :type #: Symbol? -- this group's `type:`, explicit or inferred from the spec's location
          attr_reader :resolved #: Set[Symbol] -- names of this group's `let`s resolved to a reference

          # @rbs node: RuboCop::AST::Node
          # @rbs kind: kind
          # @rbs type: Symbol?
          # @rbs carries_examples: bool
          def initialize(node:, kind:, type: nil, carries_examples: false) #: void
            @node = node
            @kind = kind
            @defs = []
            @refs = Set.new
            @refs_in_example = Set.new
            @inclusion = false
            @type = type
            @resolved = Set.new
            @carries_examples = carries_examples
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

          def shared? #: bool
            kind == :shared
          end

          # Whether an example runs in this group or in an example group nested
          # in it.
          def carries_examples? #: bool
            carries_examples
          end

          def defined_names #: Array[Symbol]
            defs.map { |_, name, _| name }
          end

          def unreferenced_defs #: Array[[ Symbol, Symbol, RuboCop::AST::Node ]]
            defs.reject { |_, name, _| resolved.include?(name) }
          end

          private

          attr_reader :carries_examples #: bool
          attr_writer :inclusion #: bool
        end
      end
    end
  end
end
