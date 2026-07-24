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

          # @rbs!
          #   def example_group?: (RuboCop::AST::Node node) -> bool
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

          # `it_behaves_like`/`it_should_behave_like` wrap the shared block in a
          # *nested* example group, so its definitions stay isolated. Every other
          # inclusion (`include_examples`/`include_context`) is *inline*: it
          # injects the shared block's definitions into the current context.
          def_node_matcher :nested_inclusion?, <<~PATTERN
            (send nil? {:it_behaves_like :it_should_behave_like} ...)
          PATTERN
        end
      end
    end
  end
end
