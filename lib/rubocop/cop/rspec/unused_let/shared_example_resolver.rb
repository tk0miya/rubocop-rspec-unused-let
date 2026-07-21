# frozen_string_literal: true

require "set"

module RuboCop
  module Cop
    module RSpec
      class UnusedLet < ::RuboCop::Cop::RSpec::Base
        # Resolves a shared example inclusion (`it_behaves_like`,
        # `include_examples`, `include_context`, ...) to the set of `let`-visible
        # names its shared block references, so the cop can treat those names as
        # referenced at the inclusion point instead of blanket-silencing every
        # `let` in scope.
        #
        # Definitions are looked up in the inspected file. `#referenced_names`
        # returns `nil` whenever the inclusion cannot be fully resolved — the
        # name is not a literal, no matching definition exists, the name is
        # defined more than once, or a nested inclusion is itself unresolvable —
        # and the caller then falls back to the conservative behavior.
        class SharedExampleResolver
          include ::RuboCop::RSpec::Language
          include ReferenceScanner
          extend ::RuboCop::AST::NodePattern::Macros

          # @rbs!
          #   def shared_group_definition: (RuboCop::AST::Node node) -> (Symbol | String)?
          #   def inclusion_call?: (RuboCop::AST::Node node) -> bool

          # @rbs @ast: RuboCop::AST::Node?
          # @rbs @index: Hash[Symbol | String, Array[RuboCop::AST::Node]]?

          def_node_matcher :shared_group_definition, <<~PATTERN
            (block (send #rspec? #SharedGroups.all ({sym str} $_) ...) ...)
          PATTERN

          def_node_matcher :inclusion_call?, "(send nil? #Includes.all ...)"

          # @rbs ast: RuboCop::AST::Node?
          def initialize(ast:) #: void
            @ast = ast
          end

          # The names the shared block pulled in by `inclusion` references,
          # transitively through nested inclusions. `nil` if unresolvable.
          #
          # @rbs inclusion: RuboCop::AST::Node
          def referenced_names(inclusion) #: Set[Symbol]?
            node = inclusion #: untyped
            name = literal_name(node.first_argument)
            return nil unless name

            collect(name, [])
          end

          private

          # @rbs name: Symbol | String
          # @rbs seen: Array[Symbol | String]
          def collect(name, seen) #: Set[Symbol]?
            return nil if seen.include?(name) # a cycle: bail conservatively

            definition = resolve_definition(name)
            return nil unless definition

            names = Set.new #: Set[Symbol]
            deeper = seen + [name]
            definition.each_descendant(:send) do |send_node|
              references_in(send_node).each { names << _1 }
              next unless inclusion_call?(send_node)

              nested = nested_names(send_node, deeper)
              return nil unless nested

              names.merge(nested)
            end
            names
          end

          # @rbs inclusion: RuboCop::AST::Node
          # @rbs seen: Array[Symbol | String]
          def nested_names(inclusion, seen) #: Set[Symbol]?
            node = inclusion #: untyped
            name = literal_name(node.first_argument)
            return nil unless name

            collect(name, seen)
          end

          # The single shared group definition registered under `name`, or `nil`
          # when it is missing or ambiguous (defined more than once).
          #
          # @rbs name: Symbol | String
          def resolve_definition(name) #: RuboCop::AST::Node?
            candidates = index[name] || []
            candidates.size == 1 ? candidates.first : nil
          end

          def index #: Hash[Symbol | String, Array[RuboCop::AST::Node]]
            @index ||= build_index
          end

          def build_index #: Hash[Symbol | String, Array[RuboCop::AST::Node]]
            index = {} #: Hash[Symbol | String, Array[RuboCop::AST::Node]]
            ast = @ast
            return index unless ast

            [ast, *ast.each_descendant(:block)].each do |node|
              name = shared_group_definition(node)
              (index[name] ||= []) << node if name
            end
            index
          end

          # @rbs arg: RuboCop::AST::Node?
          def literal_name(arg) #: (Symbol | String)?
            node = arg #: untyped
            return nil unless node&.type?(:sym, :str)

            node.value
          end
        end
      end
    end
  end
end
