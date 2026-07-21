# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpec
      class UnusedLet < ::RuboCop::Cop::RSpec::Base
        # Extracts the `let`-visible names a single send node references. Shared
        # by {ScopeBuilder} (scanning a group's own region) and
        # {SharedExampleResolver} (scanning a resolved shared block), so the
        # notion of "what counts as a reference" stays in one place.
        module ReferenceScanner
          DYNAMIC_DISPATCH_METHODS = %i[
            send public_send __send__ method respond_to?
          ].freeze

          # A bare (nil receiver) call, plus any dynamic-dispatch target such as
          # `send(:foo)` / `public_send("foo")`.
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
