# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpec
      class UnusedLet < ::RuboCop::Cop::RSpec::Base
        # The cop's traversal state: the scopes currently being descended
        # into, innermost last. Resolves a scope's references against its
        # ancestry as it is entered, and reports which of the scopes still on
        # the stack are shared groups once one is left, so the cop itself is
        # left with only lifecycle and reporting.
        class ScopeStack
          # @rbs check_helper_specs: bool
          def initialize(check_helper_specs:) #: void
            @check_helper_specs = check_helper_specs
            @stack = []
          end

          # Resolve `scope`'s references against its ancestors, then push it
          # as the new innermost scope.
          #
          # @rbs scope: Scope
          def push(scope) #: void
            mark(scope)
            stack.push(scope)
          end

          # Pop and return the innermost scope, or `nil` if the stack is
          # empty.
          def pop #: Scope?
            stack.pop
          end

          # The shared blocks among `scope` and the scopes still on the stack
          # (its ancestors), in no particular order. Call once `scope` itself
          # has been popped.
          #
          # @rbs scope: Scope
          def shared_groups_for(scope) #: Array[Scope]
            [scope, *stack].select(&:shared?)
          end

          private

          attr_reader :stack #: Array[Scope]
          attr_reader :check_helper_specs #: bool

          # Resolve `scope`'s references against its ancestors and mark every
          # definition they reach. `scope` is not on the stack yet, so
          # `stack` is exactly its ancestors.
          #
          # @rbs scope: Scope
          def mark(scope) #: void
            mark_upward(scope)
            mark_downward(scope)
            mark_referenced_all(scope) if scope.inclusion || ignore_helper_spec?(scope)
          end

          # A reference made in this group, whether in an example or a helper
          # body, reaches a `let` defined here or in an enclosing group.
          #
          # @rbs scope: Scope
          def mark_upward(scope) #: void
            (scope.refs | scope.refs_in_example).each do |name|
              scope.mark_referenced(name)
              stack.each { _1.mark_referenced(name) }
            end
          end

          # A helper body in an enclosing group can reference a `let` defined
          # here, since it runs in the example's scope.
          #
          # @rbs scope: Scope
          def mark_downward(scope) #: void
            scope.defined_names.each do |name|
              scope.mark_referenced(name) if stack.any? { _1.refs.include?(name) }
            end
          end

          # A helper spec's auto-included module lives in another file and may
          # reference any `let` in scope, so every definition is treated as
          # referenced unless `CheckHelperSpecs` opts in. This judgement is
          # independent of shared inclusions.
          #
          # @rbs scope: Scope
          def ignore_helper_spec?(scope) #: bool
            return false if check_helper_specs

            helper_spec?(scope)
          end

          # The effective `type:` is the innermost one in the group's
          # ancestry (each scope already carries its explicit type, or
          # `:helper` inferred from a `spec/helpers` location).
          #
          # @rbs scope: Scope
          def helper_spec?(scope) #: bool
            [scope, *stack].filter_map(&:type).first == :helper
          end

          # Treat every `let` visible in `scope` (its own and its ancestors')
          # as referenced. Used where references can't be fully seen from
          # this file: a shared inclusion, or a helper spec's auto-included
          # module.
          #
          # @rbs scope: Scope
          def mark_referenced_all(scope) #: void
            [scope, *stack].each do |group|
              group.defined_names.each { group.mark_referenced(_1) }
            end
          end
        end
      end
    end
  end
end
