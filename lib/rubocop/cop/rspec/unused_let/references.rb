# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpec
      class UnusedLet < ::RuboCop::Cop::RSpec::Base
        # The `let`-visible names a single send node references. Shared by
        # {ScopeBuilder} and {SharedExampleRegistry} so both read references the
        # same way.
        module References
          DYNAMIC_DISPATCH_METHODS = %i[
            send public_send __send__ method respond_to?
          ].freeze

          # Calls that reach the group's `subject` without naming it: RSpec's
          # one-liner syntax (`is_expected`, `should`, `should_not`, and
          # rspec-collection_matchers' plural `are_expected`) and rspec-its
          # (`its(:size) { ... }`, which derives from the subject). Normalizing
          # them here is what lets a `subject` be resolved by the same machinery
          # as a `let`, in a shared block as much as in a group.
          SUBJECT_ALIASES = %i[is_expected are_expected should should_not its].freeze

          module_function

          # A bare (nil receiver) call names a `let`; a dynamic-dispatch call
          # such as `send(:foo)` names its literal first argument.
          #
          # @rbs node: RuboCop::AST::Node
          def references_in(node) #: Array[Symbol]
            return [] unless node.send_type?

            send = node #: untyped
            names = [] #: Array[Symbol]
            if send.receiver.nil?
              names << send.method_name
              names << :subject if SUBJECT_ALIASES.include?(send.method_name)
            end
            if DYNAMIC_DISPATCH_METHODS.include?(send.method_name)
              arg = send.first_argument
              names << arg.value.to_sym if arg&.type?(:sym, :str)
            end
            names
          end
        end
      end
    end
  end
end
