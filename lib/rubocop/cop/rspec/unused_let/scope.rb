# frozen_string_literal: true

require "set"

require_relative "matchers"

module RuboCop
  module Cop
    module RSpec
      class UnusedLet < ::RuboCop::Cop::RSpec::Base
        # A mutable record of one example or shared group: the definitions it
        # makes, the references it makes (kept apart by whether they sit in a
        # helper body or in an example), whether an example runs in it, whether
        # it pulls in a shared example group, and which of its definitions have
        # been resolved to a reference.
        class Scope
          # @rbs! type kind = :example | :shared

          # One definition a group makes: a `let`/`let!`, a `subject`/`subject!`
          # or a `def` helper method.
          Definition = Struct.new(
            :helper,  #: Symbol -- `:let`, `:let!`, `:subject`, `:subject!` or `:def`
            :name,    #: Symbol? -- the declared name used in the message, `nil` for an anonymous `subject`
            :names,   #: Array[Symbol] -- every name that reaches it: the declared name and any alias
            :node     #: RuboCop::AST::Node
          )

          # Reopened rather than given a `Struct.new` block, whose body
          # `rbs-inline` does not read.
          class Definition
            def subject? #: bool
              Matchers::SUBJECT_HELPERS.include?(helper)
            end

            def bang? #: bool
              Matchers::BANG_HELPERS.include?(helper)
            end

            def def_helper? #: bool
              helper == :def
            end

            def anonymous? #: bool
              name.nil?
            end
          end

          attr_reader :node #: RuboCop::AST::Node
          attr_reader :kind #: kind
          attr_reader :defs #: Array[Definition] -- one per `let`, `subject` or `def` helper
          attr_reader :refs #: Set[Symbol] -- names referenced in this group's helper bodies
          attr_reader :refs_in_example #: Set[Symbol] -- names referenced outside this group's helper bodies
          attr_reader :inclusion #: bool -- whether this group pulls in a shared example group
          attr_reader :type #: Symbol? -- this group's `type:`, explicit or inferred from the spec's location
          attr_reader :resolved #: Set[Symbol] -- names of this group's definitions resolved to a reference

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
          # @rbs name: Symbol?
          # @rbs def_node: RuboCop::AST::Node
          # @rbs alias_name: Symbol?
          def add_definition(helper, name, def_node, alias_name: nil) #: void
            defs << Definition.new(helper, name, [name, alias_name].compact.uniq, def_node)
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
            defs.flat_map(&:names).uniq
          end

          def unreferenced_defs #: Array[Definition]
            defs.reject { |definition| definition.names.any? { resolved.include?(_1) } }
          end

          private

          attr_reader :carries_examples #: bool
          attr_writer :inclusion #: bool
        end
      end
    end
  end
end
