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

          module_function

          # A bare (nil receiver) call names a `let`; a dynamic-dispatch call
          # such as `send(:foo)` names its literal first argument.
          #
          # @rbs node: RuboCop::AST::Node
          def references_in(node) #: Array[Symbol]
            return [] unless node.send_type?

            send = node #: untyped
            names = [] #: Array[Symbol]
            names << send.method_name if send.receiver.nil?
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
