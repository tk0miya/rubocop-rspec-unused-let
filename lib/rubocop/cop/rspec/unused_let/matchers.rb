# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpec
      class UnusedLet < ::RuboCop::Cop::RSpec::Base
        # The RSpec node-pattern matchers this cop uses to recognize AST nodes:
        # example/shared groups, `let`/`subject` definitions, and shared-example
        # inclusions.
        module Matchers
          include ::RuboCop::RSpec::Language
          extend ::RuboCop::AST::NodePattern::Macros

          # Node types that open a new method-definition scope (a new
          # `self`/definee): a `def` nested inside one defines a method there,
          # not an instance method on the surrounding example group's class.
          DEFINEE_SCOPE_TYPES = %i[def defs class module sclass].freeze

          # @rbs node: RuboCop::AST::Node
          def definee_scope?(node) #: bool
            DEFINEE_SCOPE_TYPES.include?(node.type)
          end

          # @rbs!
          #   def example_group?: (RuboCop::AST::Node node) -> bool
          #   def example_send?: (RuboCop::AST::Node node) -> bool
          #   def spec_group?: (RuboCop::AST::Node node) -> bool
          #   def shared_group_name: (RuboCop::AST::Node node) -> (Symbol | String)?
          #   def let_definition: (RuboCop::AST::Node node) -> [ Symbol, (Symbol | String) ]?
          #   def subject_definition_name: (RuboCop::AST::Node node) -> Symbol?
          #   def inclusion_call?: (RuboCop::AST::Node node) -> bool
          #   def inclusion_name: (RuboCop::AST::Node node) -> (Symbol | String)?
          #   def nested_inclusion?: (RuboCop::AST::Node node) -> bool

          def_node_matcher :example_group?, <<~PATTERN
            (block (send #rspec? #ExampleGroups.all ...) ...)
          PATTERN

          # The `send` of an example (`it`, `specify`, ...), with or without a
          # block, so a pending `it "does something"` matches too. Named apart
          # from `RuboCop::RSpec::Language#example?`, which this module includes
          # and which matches the surrounding block node instead.
          def_node_matcher :example_send?, <<~PATTERN
            (send nil? #Examples.all ...)
          PATTERN

          def_node_matcher :spec_group?, <<~PATTERN
            (block (send #rspec? {#ExampleGroups.all #SharedGroups.all} ...) ...)
          PATTERN

          def_node_matcher :shared_group_name, <<~PATTERN
            (block (send #rspec? #SharedGroups.all ({sym str} $_) ...) ...)
          PATTERN

          def_node_matcher :let_definition, <<~PATTERN
            {
              (block (send nil? ${:let :let!} ({sym str} $_) ...) ...)
              (send nil? ${:let :let!} ({sym str} $_) block_pass)
            }
          PATTERN

          def_node_matcher :subject_definition_name, <<~PATTERN
            (block (send nil? {:subject :subject!} (sym $_) ...) ...)
          PATTERN

          def_node_matcher :inclusion_call?, "(send nil? #Includes.all ...)"

          def_node_matcher :inclusion_name, <<~PATTERN
            (send nil? #Includes.all ({sym str} $_) ...)
          PATTERN

          # `it_behaves_like`/`it_should_behave_like` are the inclusions that wrap
          # the shared block in a nested example group.
          def_node_matcher :nested_inclusion?, <<~PATTERN
            (send nil? {:it_behaves_like :it_should_behave_like} ...)
          PATTERN

          # An *inline* inclusion (`include_examples`/`include_context`) injects
          # the shared block's definitions into the current context, where a
          # nested one isolates them in its own group. Any inclusion not
          # recognized as nested counts as inline, so an unknown form errs toward
          # suppressing a same-named `let` rather than risking a false positive.
          #
          # @rbs node: RuboCop::AST::Node
          def inline_inclusion?(node) #: bool
            inclusion_call?(node) && !nested_inclusion?(node)
          end
        end
      end
    end
  end
end
