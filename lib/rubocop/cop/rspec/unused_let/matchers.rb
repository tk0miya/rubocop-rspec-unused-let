# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpec
      class UnusedLet < ::RuboCop::Cop::RSpec::Base
        # The RSpec vocabulary this cop works from, and the node-pattern
        # matchers that recognize it in an AST: example/shared groups,
        # `let`/`subject` definitions, and shared-example inclusions.
        module Matchers
          include ::RuboCop::RSpec::Language
          extend ::RuboCop::AST::NodePattern::Macros

          # Node types that open a new method-definition scope by keyword.
          DEFINEE_SCOPE_TYPES = %i[def defs class module sclass].freeze

          # The helpers that declare a subject.
          SUBJECT_HELPERS = %i[subject subject!].freeze

          # The helpers whose block runs eagerly, so it may exist for its side
          # effects alone.
          BANG_HELPERS = %i[let! subject!].freeze

          # Whether `node` opens a method-definition scope (a new
          # `self`/definee) of its own, by keyword or as a block: a `def`
          # nested inside one defines a method there, not an instance method on
          # the surrounding example group's class.
          #
          # @rbs node: RuboCop::AST::Node
          def definee_scope?(node) #: bool
            DEFINEE_SCOPE_TYPES.include?(node.type) || definee_block?(node)
          end

          # @rbs!
          #   def definee_block?: (RuboCop::AST::Node node) -> bool
          #   def example_group?: (RuboCop::AST::Node node) -> bool
          #   def example_send?: (RuboCop::AST::Node node) -> bool
          #   def spec_group?: (RuboCop::AST::Node node) -> bool
          #   def shared_group_name: (RuboCop::AST::Node node) -> (Symbol | String)?
          #   def let_definition: (RuboCop::AST::Node node) -> [ Symbol, (Symbol | String) ]?
          #   def named_subject_definition: (RuboCop::AST::Node node) -> [ Symbol, (Symbol | String) ]?
          #   def anonymous_subject_definition: (RuboCop::AST::Node node) -> Symbol?
          #   def inclusion_call?: (RuboCop::AST::Node node) -> bool
          #   def inclusion_name: (RuboCop::AST::Node node) -> (Symbol | String)?
          #   def nested_inclusion?: (RuboCop::AST::Node node) -> bool

          # The blocks that run their body against a definee of their own: the
          # anonymous class builders a spec uses for stub classes, and the
          # `*_eval`/`*_exec` family, which defines methods on its receiver.
          def_node_matcher :definee_block?, <<~PATTERN
            (any_block
              {
                (send (const {nil? cbase} {:Class :Module :Struct}) :new ...)
                (send (const {nil? cbase} :Data) :define ...)
                (send !nil? {:class_eval :module_eval :instance_eval
                             :class_exec :module_exec :instance_exec} ...)
              }
              ...)
          PATTERN

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

          def_node_matcher :named_subject_definition, <<~PATTERN
            (block (send nil? ${:subject :subject!} ({sym str} $_) ...) ...)
          PATTERN

          def_node_matcher :anonymous_subject_definition, <<~PATTERN
            (block (send nil? ${:subject :subject!}) ...)
          PATTERN

          # `[helper, name]` for a subject definition, with `name` `nil` for an
          # anonymous `subject { }`; `nil` when the node defines no subject.
          #
          # @rbs node: RuboCop::AST::Node
          def subject_definition(node) #: [ Symbol, Symbol? ]?
            if (named = named_subject_definition(node))
              [named[0], named[1].to_sym]
            elsif (helper = anonymous_subject_definition(node))
              [helper, nil]
            end
          end

          # Whether `node` is the `subject`/`subject!` call declaring a subject:
          # it heads a block of any kind, or takes one as an argument. Such a
          # call names the subject it declares, not one defined further out, so
          # it must not be read as a reference the way a bare `subject` call is.
          #
          # Deliberately wider than {#subject_definition}, which recognizes only
          # the form rubocop-rspec collects as a definition: a declaration the
          # cop cannot check should not silence a subject elsewhere either.
          #
          # @rbs node: RuboCop::AST::Node
          def subject_definition_head?(node) #: bool
            return false unless node.send_type?

            send = node #: untyped
            return false unless send.receiver.nil? && SUBJECT_HELPERS.include?(send.method_name)

            send.block_literal? || send.last_argument&.block_pass_type? || false
          end

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
