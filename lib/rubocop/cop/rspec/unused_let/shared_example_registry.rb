# frozen_string_literal: true

require_relative "matchers"
require_relative "references"

module RuboCop
  module Cop
    module RSpec
      class UnusedLet < ::RuboCop::Cop::RSpec::Base
        # A file-wide index of the `shared_examples`/`shared_context` blocks
        # defined in the source under investigation.
        #
        # RuboCop analyzes one file at a time, so a shared block defined in
        # *another* file is invisible and any inclusion of it must stay
        # conservative. But when the definition lives in the same file we can
        # read exactly which `let`-visible names it consumes — its *free
        # references*: the names referenced anywhere in its subtree that it does
        # not itself define. An inclusion then only needs to justify those
        # names, instead of silencing every `let` in scope.
        #
        # Lookup follows RSpec's own scoping. A `shared_examples` inside a group
        # is visible only to that group and its descendants, and an inner
        # definition shadows an outer one of the same name. {#resolve} therefore
        # takes the inclusion node and walks its enclosing groups from the
        # innermost outward (then the file's top level), returning the *nearest*
        # matching definition — mirroring how RSpec picks which shared block a
        # name refers to.
        #
        # {#resolve} returns the free references for the resolved name, or `nil`
        # when no definition is visible or it cannot be resolved (a dynamic or
        # unknown nested inclusion, or an inclusion cycle) — in which case the
        # caller falls back to treating every visible `let` as referenced.
        class SharedExampleRegistry
          include Matchers
          include References

          # One shared block's region data, gathered across its whole subtree.
          Definition = Struct.new(
            :owner,      #: RuboCop::AST::Node? -- nearest enclosing group (nil = top level), where it is visible
            :node,       #: RuboCop::AST::Node -- the shared block node itself
            :refs,       #: Set[Symbol] -- names the block references
            :defs,       #: Set[Symbol] -- names the block defines
            :inclusions  #: Array[[ String?, RuboCop::AST::Node ]] -- included blocks, each with its inclusion node
          )

          # @rbs ast: RuboCop::AST::Node?
          def initialize(ast) #: void
            @definitions = {} #: Hash[String, Array[Definition]]
            scan(ast) if ast
          end

          # The free references an inclusion of `name` at `inclusion_node`
          # consumes, or `nil` when no definition is visible or it cannot be
          # resolved.
          #
          # @rbs name: Symbol | String
          # @rbs inclusion_node: RuboCop::AST::Node
          def resolve(name, inclusion_node) #: Set[Symbol]?
            resolve_from(name.to_s, inclusion_node, [])
          end

          private

          attr_reader :definitions #: Hash[String, Array[Definition]]

          # Index every shared block in the file under its name. Names can carry
          # more than one definition (in different scopes, or a same-scope
          # redefinition), disambiguated at lookup time by scope.
          #
          # @rbs ast: RuboCop::AST::Node
          def scan(ast) #: void
            [ast, *ast.each_descendant(:block)].each do |node|
              name = shared_group_name(node)
              (definitions[name.to_s] ||= []) << build_definition(node) if name
            end
          end

          # @rbs node: RuboCop::AST::Node
          def build_definition(node) #: Definition
            definition = Definition.new(enclosing_group(node), node, Set.new, Set.new, [])
            node.each_descendant(:send, :block) { classify(_1, definition) }
            definition
          end

          # Sort one subtree node into the shared block's definitions,
          # references or nested inclusions.
          #
          # @rbs child: RuboCop::AST::Node
          # @rbs definition: Definition
          def classify(child, definition) #: void
            if (let = let_definition(child))
              definition.defs << let[1].to_sym
            elsif (name = subject_definition_name(child))
              definition.defs << name
            elsif child.send_type?
              classify_send(child, definition)
            end
          end

          # A bare send inside a shared block is either an inclusion of another
          # shared block (recorded for nested resolution) or a plain reference.
          #
          # @rbs child: RuboCop::AST::Node
          # @rbs definition: Definition
          def classify_send(child, definition) #: void
            if inclusion_call?(child)
              definition.inclusions << [inclusion_name(child)&.to_s, child]
            else
              references_in(child).each { definition.refs << _1 }
            end
          end

          # The nearest example/shared group enclosing `node`, or `nil` when it
          # sits at the file's top level.
          #
          # @rbs node: RuboCop::AST::Node
          def enclosing_group(node) #: RuboCop::AST::Node?
            node.each_ancestor(:block).find { spec_group?(_1) }
          end

          # @rbs name: String
          # @rbs inclusion_node: RuboCop::AST::Node
          # @rbs stack: Array[RuboCop::AST::Node]
          def resolve_from(name, inclusion_node, stack) #: Set[Symbol]?
            definition = lookup(name, inclusion_node)
            return nil unless definition # unknown here -> conservative

            free_references(definition, stack)
          end

          # The definition of `name` that RSpec would apply at `inclusion_node`:
          # the innermost enclosing group that defines the name wins (shadowing
          # outer ones), falling back to the file's top-level definitions. Within
          # the winning scope the last definition wins, mirroring RSpec, which
          # warns on a redefinition and keeps the latest. `nil` when no
          # definition is visible here.
          #
          # @rbs name: String
          # @rbs inclusion_node: RuboCop::AST::Node
          def lookup(name, inclusion_node) #: Definition?
            candidates = definitions[name]
            return nil unless candidates

            inclusion_node.each_ancestor(:block) do |group|
              next unless spec_group?(group)

              found = candidates.select { _1.owner&.equal?(group) }.last
              return found if found
            end
            candidates.select { _1.owner.nil? }.last
          end

          # The free references the definition consumes: the names it references
          # but does not define, plus the free references of the blocks it
          # includes (reduced by its own definitions). `nil` if it is part of a
          # cycle, or includes something dynamic or itself unresolvable.
          #
          # @rbs definition: Definition
          # @rbs stack: Array[RuboCop::AST::Node]
          def free_references(definition, stack) #: Set[Symbol]?
            return nil if stack.include?(definition.node) # cycle -> conservative

            nested = nested_references(definition, stack)
            return nil if nested.nil?

            (definition.refs - definition.defs) | nested
          end

          # The free references reaching `definition` through the shared blocks
          # it includes, reduced by the names it defines itself. `nil` if any
          # nested inclusion is dynamic or unresolvable.
          #
          # @rbs definition: Definition
          # @rbs stack: Array[RuboCop::AST::Node]
          def nested_references(definition, stack) #: Set[Symbol]?
            result = Set.new #: Set[Symbol]

            definition.inclusions.each do |name, node|
              return nil unless name # dynamic inclusion -> conservative

              nested = resolve_from(name, node, stack + [definition.node])
              return nil unless nested # unknown/cyclic nested -> conservative

              result |= (nested - definition.defs)
            end

            result
          end
        end
      end
    end
  end
end
