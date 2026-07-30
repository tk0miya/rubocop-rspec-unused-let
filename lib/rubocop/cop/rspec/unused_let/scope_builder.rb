# frozen_string_literal: true

require_relative "matchers"
require_relative "references"

module RuboCop
  module Cop
    module RSpec
      class UnusedLet < ::RuboCop::Cop::RSpec::Base
        # Turns an example/shared group AST node into a {Scope}, collecting the
        # group's own definitions and references (but not those of nested groups,
        # which become their own scopes). This is the only part of the cop that
        # needs RSpec's node-pattern matchers, so it is kept out of both the cop
        # (RuboCop lifecycle) and {Scope} (pure data and queries).
        class ScopeBuilder
          include Matchers
          include References

          # rspec-rails infers `type: :helper` for spec files under `spec/helpers`.
          HELPER_SPEC_PATH = %r{(?:^|/)spec/helpers/}.freeze

          # The block node types: `{ |x| }` parses as `block`, `{ _1 }` as
          # `numblock` and Ruby 3.4's `{ it }` as `itblock`.
          BLOCK_TYPES = %i[block numblock itblock].freeze

          # Every node type whose body holds code at a remove from the group it
          # is written in, hiding an example selector from {#example_of?}.
          # Anything that opens a new definee qualifies: code that does not run
          # in the group's own scope cannot be defining one of its examples.
          ENCLOSING_BODY_TYPES = (BLOCK_TYPES + Matchers::DEFINEE_SCOPE_TYPES).freeze

          # `let` names that well-known gems' shared contexts implicitly
          # reference, hidden from single-file analysis, keyed by the `type:`
          # metadata that pulls the shared context in. When a group carries a
          # matching `type:`, the listed names are recorded as references so
          # that `let`s of those names (here or in a descendant) count as used.
          IMPLICIT_REFS_BY_TYPE = {
            # rspec-validator_spec_helper
            # https://github.com/izumin5210/rspec-validator_spec_helper
            # `type: :validator` triggers a shared subject that dereferences
            # these names via `eval`, hidden from static analysis.
            validator: %i[
              value attribute_names options
              validator_name validator_class validator_type validation_name
              model_class
            ].freeze
          }.freeze

          # @rbs spec_filename: String?
          # @rbs registry: SharedExampleRegistry
          def initialize(spec_filename, registry) #: void
            @spec_filename = spec_filename
            @registry = registry
          end

          # Build the Scope for `node` from its own region alone; nested groups
          # are left for their own traversal.
          #
          # @rbs node: RuboCop::AST::Node
          def build_from(node) #: Scope
            kind = example_group?(node) ? :example : :shared #: Scope::kind
            type = type_from_group(node) || type_from_filename(spec_filename)
            scope = Scope.new(node: node, kind: kind, type: type, carries_examples: carries_examples?(node))
            helpers = helper_nodes(node)
            collect_definitions(node, scope)
            helpers.each { record_helper_references(_1, scope) }
            collect_example_references(node, scope, helpers)
            inject_implicit_references(scope)
            scope
          end

          private

          attr_reader :spec_filename #: String?
          attr_reader :registry #: SharedExampleRegistry

          # Whether `node` carries an example: one it would run itself, its
          # nested example groups included. For a shared block this has to come
          # from the contents, since the keyword that opened it says nothing:
          # RSpec makes `shared_examples` and `shared_context` aliases.
          #
          # @rbs node: RuboCop::AST::Node
          def carries_examples?(node) #: bool
            node.each_descendant(:send).any? { example_send?(_1) && example_of?(_1, node) }
          end

          # Whether `node` would run `example_send` as one of its own examples,
          # rather than merely holding the name: only a nested example group and
          # the example's own block may sit between the two.
          #
          # What tells the two roles of `skip`/`pending` apart is position: at a
          # group's level the call defines a pending example, while inside any
          # other body — a hook, an example, a `let`, a `def` helper — it acts on
          # the example already running.
          #
          # @rbs example_send: RuboCop::AST::Node
          # @rbs node: RuboCop::AST::Node
          def example_of?(example_send, node) #: bool
            example_send
              .each_ancestor(*ENCLOSING_BODY_TYPES)
              .take_while { !_1.equal?(node) }
              .all? { example_group?(_1) || own_block_of?(_1, example_send) }
          end

          # Whether `candidate` is the example's own block, as in `it { ... }`.
          #
          # @rbs candidate: RuboCop::AST::Node
          # @rbs example_send: RuboCop::AST::Node
          def own_block_of?(candidate, example_send) #: bool
            return false unless candidate.type?(*BLOCK_TYPES)

            node = candidate #: untyped
            node.send_node.equal?(example_send)
          end

          # A well-known gem's shared context (pulled in by `type:` metadata)
          # can reference `let` names that single-file analysis never sees.
          # Record them exactly as a real helper on this group would be: an
          # example reference (justifying a `let` here or in an ancestor) *and* a
          # helper reference (reaching `let`s in descendant groups, since helper
          # bodies run in the example's scope).
          #
          # @rbs scope: Scope
          def inject_implicit_references(scope) #: void
            names = scope.type && IMPLICIT_REFS_BY_TYPE[scope.type]
            return unless names

            names.each do |name|
              scope.add_reference_in_example(name)
              scope.add_reference(name)
            end
          end

          # @rbs node: RuboCop::AST::Node
          # @rbs scope: Scope
          def collect_definitions(node, scope) #: void
            RuboCop::RSpec::ExampleGroup.new(node).lets.each do |let|
              helper, name = let_definition(let)
              scope.add_definition(helper, name.to_sym, let) if helper && name
            end
            collect_method_definitions(node, scope)
          end

          # `def foo` at an example group's level becomes an instance method on
          # the group's example class, so it is a definition just like a `let`.
          #
          # @rbs node: RuboCop::AST::Node
          # @rbs scope: Scope
          def collect_method_definitions(node, scope) #: void
            method_definitions_in(node).each do |defn|
              inner = defn #: untyped
              scope.add_definition(:def, inner.method_name, defn)
            end
          end

          # References in `node`'s region that sit *outside* its helper bodies
          # (examples and any other group-level code), collected into
          # `refs_in_example`. Stops at nested spec groups and skips the helper
          # definitions, whose references belong to `refs`. Resolves a shared
          # inclusion found along the way.
          #
          # @rbs node: RuboCop::AST::Node
          # @rbs scope: Scope
          # @rbs helpers: Array[RuboCop::AST::Node]
          def collect_example_references(node, scope, helpers) #: void
            node.each_child_node do |child|
              next if spec_group?(child) || helpers.any? { _1.equal?(child) }

              references_in(child).each { scope.add_reference_in_example(_1) }
              record_inclusion(child, scope) if inclusion_call?(child)
              collect_example_references(child, scope, helpers)
            end
          end

          # A shared inclusion whose block is defined in this file consumes only
          # its free references, recorded like any other example reference. An
          # inclusion we cannot resolve (an unknown or dynamically named block)
          # falls back to silencing every `let` visible at this point. An inline
          # inclusion additionally reaches a same-named `let` here through its
          # bound references, via {#mark_inline_bound_references}.
          #
          # @rbs node: RuboCop::AST::Node
          # @rbs scope: Scope
          def record_inclusion(node, scope) #: void
            name = inclusion_name(node)
            free_refs = name && registry.resolve(name, node)
            unless name && free_refs
              scope.mark_inclusion
              return
            end

            free_refs.each { scope.add_reference_in_example(_1) }
            mark_inline_bound_references(name, node, scope) if inline_inclusion?(node)
          end

          # An inline inclusion injects the block's definitions here, so its bound
          # references (names it both defines and references) reach a same-named
          # `let` in this scope — mark those referenced. Scoped to this group's
          # own definitions, so it never suppresses an unrelated `let` in an
          # ancestor or descendant group.
          #
          # @rbs name: Symbol | String
          # @rbs node: RuboCop::AST::Node
          # @rbs scope: Scope
          def mark_inline_bound_references(name, node, scope) #: void
            registry.bound_references(name, node).each { scope.mark_referenced(_1) }
          end

          # The group's own `let`/`subject`/hook/`def` definitions, whose bodies
          # run in the example's scope.
          #
          # @rbs node: RuboCop::AST::Node
          def helper_nodes(node) #: Array[RuboCop::AST::Node]
            group = RuboCop::RSpec::ExampleGroup.new(node)
            group.lets +
              group.subjects +
              group.hooks.map(&:to_node) +
              method_definitions_in(node)
          end

          # @rbs node: RuboCop::AST::Node
          # @rbs scope: Scope
          def record_helper_references(node, scope) #: void
            references_in(node).each { scope.add_reference(_1) }
            node.each_child_node { record_helper_references(_1, scope) }
          end

          # `def foo` written at an example group's level becomes an instance
          # method on the group's example class. Skip `def`s that belong
          # elsewhere: nested inside a deeper example/shared group (not visible
          # from `node`), or inside a `class`/`module`/`def` written in the group
          # (which define methods on that inner scope, not on the example class).
          #
          # @rbs node: RuboCop::AST::Node
          def method_definitions_in(node) #: Array[RuboCop::AST::Node]
            node.each_descendant(:def).select { own_level_method?(_1, node) }
          end

          # Whether `defn` defines an instance method on `group`'s example class:
          # walking outward, `group` is reached before any nested spec group or
          # inner definee scope (`class`/`module`/`def`/...) that would claim it.
          #
          # @rbs defn: RuboCop::AST::Node
          # @rbs group: RuboCop::AST::Node
          def own_level_method?(defn, group) #: bool
            defn.each_ancestor do |ancestor|
              return true if ancestor.equal?(group)
              return false if spec_group?(ancestor) || definee_scope?(ancestor)
            end
            false
          end

          # @rbs node: RuboCop::AST::Node
          def type_from_group(node) #: Symbol?
            block = node #: untyped
            block.send_node.arguments.each do |arg|
              next unless arg.hash_type?

              arg.pairs.each do |pair|
                key = pair.key
                value = pair.value
                return value.value if key.sym_type? && key.value == :type && value.sym_type?
              end
            end
            nil
          end

          # rspec-rails infers a spec's `type:` from its location when none is
          # set explicitly. Only `:helper` is inferred here, the one type the
          # cop acts on.
          #
          # @rbs filename: String?
          def type_from_filename(filename) #: Symbol?
            :helper if filename && HELPER_SPEC_PATH.match?(filename)
          end
        end
      end
    end
  end
end
