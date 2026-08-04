# frozen_string_literal: true

require "digest"

require_relative "unused_let/matchers"
require_relative "unused_let/references"
require_relative "unused_let/scope"
require_relative "unused_let/scope_builder"
require_relative "unused_let/shared_example_registry"

module RuboCop
  module Cop
    module RSpec
      # Checks for `let`/`subject` definitions and helper methods that are never
      # referenced.
      #
      # A `let` (or `let!`) whose name is never used within its scope is dead
      # code that makes specs harder to read. This cop flags such definitions.
      # A helper method (`def`) written at an example group's level becomes an
      # instance method on the group's example class, so it is checked the same
      # way. A `subject` (or `subject!`) is checked too: it answers both to its
      # own name, when it has one, and to the implicit name `subject`, which
      # `is_expected`, `are_expected`, `should`, `should_not` and rspec-its'
      # `its` reach.
      # Dynamic references count as usages too: a call to `send`, `public_send`,
      # `__send__`, `method` or `respond_to?` with a literal name (e.g.
      # `send(:foo)`) references the `let` or method it names.
      #
      # Because RuboCop analyzes one file at a time, the cop stays silent
      # wherever it cannot see every possible reference: `let`s inside a
      # `shared_examples`/`shared_context` block that carries no examples (a
      # provider, whose `let`s exist for the including group), `let`s visible at
      # an inclusion whose shared block it cannot find, `let`s a well-known
      # gem's shared context consumes implicitly (recognized by the group's
      # `type:` metadata), and helper specs. Where it can see the shared block,
      # only the `let`s that block references are treated as used and the rest
      # stay checked. `SharedExamplePaths` lists the files it pre-loads to see
      # blocks defined elsewhere, and defaults to `spec/support/**/*.rb` — the
      # glob rspec-rails offers for requiring support files. See
      # {https://github.com/tk0miya/rubocop-rspec-unused-let#readme the README}
      # for the exact rules and their known limitations.
      #
      # @example
      #   # bad
      #   describe Foo do
      #     let(:used) { 1 }
      #     let(:unused) { 2 }
      #
      #     it { expect(used).to eq(1) }
      #   end
      #
      #   # good
      #   describe Foo do
      #     let(:used) { 1 }
      #
      #     it { expect(used).to eq(1) }
      #   end
      #
      # @example a helper method
      #   # bad
      #   describe Foo do
      #     def unused
      #       1
      #     end
      #
      #     it { expect(true).to be(true) }
      #   end
      #
      #   # good
      #   describe Foo do
      #     def used
      #       1
      #     end
      #
      #     it { expect(used).to eq(1) }
      #   end
      #
      # @example a subject
      #   # bad
      #   describe Foo do
      #     subject { described_class.new }
      #
      #     it { expect(Foo.count).to eq(0) }
      #   end
      #
      #   # good - the one-liner syntax references the subject
      #   describe Foo do
      #     subject { described_class.new }
      #
      #     it { is_expected.to be_valid }
      #   end
      #
      #   # good - a named subject may be referenced by either name
      #   describe Foo do
      #     subject(:widget) { described_class.new }
      #
      #     it { expect(widget).to be_valid }
      #   end
      #
      # @example a same-named `let` in the including group
      #   RSpec.shared_examples "uses size" do
      #     let(:size) { 1 }
      #     it { expect(size).to be_positive }
      #   end
      #
      #   # good - `include_examples` injects the block here, so this `let` is
      #   # the override it uses
      #   describe Foo do
      #     include_examples "uses size"
      #     let(:size) { 2 }
      #   end
      #
      #   # bad - `it_behaves_like` runs the block in its own group, which uses
      #   # its own `let(:size)`
      #   describe Bar do
      #     it_behaves_like "uses size"
      #     let(:size) { 2 }
      #   end
      #
      # @example CheckLetBang: true (default)
      #   # bad - applies to `subject!` as well as `let!`
      #   describe Foo do
      #     let!(:widget) { create(:widget) }
      #
      #     it { expect(Widget.count).to eq(1) }
      #   end
      #
      # @example CheckLetBang: false
      #   # good - `let!` is assumed to be used for its side effects
      #   describe Foo do
      #     let!(:widget) { create(:widget) }
      #
      #     it { expect(Widget.count).to eq(1) }
      #   end
      #
      # @example CheckSubject: true (default)
      #   # bad
      #   describe Foo do
      #     subject(:widget) { described_class.new }
      #
      #     it { expect(Foo.count).to eq(0) }
      #   end
      #
      # @example CheckSubject: false
      #   # good - a `subject` is left alone even when nothing references it
      #   describe Foo do
      #     subject(:widget) { described_class.new }
      #
      #     it { expect(Foo.count).to eq(0) }
      #   end
      #
      # @example CheckHelperSpecs: false (default)
      #   # good - a helper spec's `let`s may be referenced by the auto-included
      #   # module's methods, so they are not flagged
      #   describe MyHelper, type: :helper do
      #     let(:current_user) { User.new }
      #
      #     it { expect(helper.greeting).to eq("Hi") }
      #   end
      #
      # @example CheckHelperSpecs: true
      #   # bad - helper specs are checked like any other group
      #   describe MyHelper, type: :helper do
      #     let(:unused) { 1 }
      #
      #     it { expect(helper.greeting).to eq("Hi") }
      #   end
      #
      # @example CheckSharedExamples: true (default)
      #   # bad - the block carries examples, so it is meant to be run rather
      #   # than to supply `let`s to its includer, and is checked like any group
      #   RSpec.shared_examples "a thing" do
      #     let(:unused) { 1 }
      #
      #     it { expect(value).to eq(1) }
      #   end
      #
      #   # good - no examples, so the block is a provider pulled in with
      #   # `include_context` and its `let`s stay unchecked
      #   RSpec.shared_context "with a thing" do
      #     let(:provided) { 1 }
      #   end
      #
      # @example CheckSharedExamples: false
      #   # good - every `let` inside a shared block is left alone, in case a
      #   # group including the block references it from another file
      #   RSpec.shared_examples "a thing" do
      #     let(:unused) { 1 }
      #
      #     it { expect(value).to eq(1) }
      #   end
      #
      # @safety
      #   Autocorrect deletes the flagged definition. That is behaviorally safe
      #   for a plain `let` or `subject`, whose block never runs when the helper
      #   is unreferenced, but a `let!`/`subject!` block is executed eagerly and
      #   may exist purely for its side effects. RuboCop treats autocorrect
      #   safety as a whole-cop setting, so the cop is marked unsafe and every
      #   flagged definition is only removed under `rubocop --autocorrect-all`.
      #
      #   Inside a shared block that carries examples the cop never follows an
      #   inclusion site back to the block, so a definition only an including
      #   group references is removed. Set `CheckSharedExamples: false` to leave
      #   shared blocks alone.
      class UnusedLet < ::RuboCop::Cop::RSpec::Base
        extend AutoCorrector

        include RangeHelp

        MSG = "`%<helper>s(:%<name>s)` is not referenced anywhere. " \
              "Remove it or reference it in an example."
        DEF_MSG = "`def %<name>s` is not referenced anywhere. " \
                  "Remove it or reference it in an example."
        ANONYMOUS_SUBJECT_MSG = "`%<helper>s` is not referenced anywhere. " \
                                "Remove it or reference it in an example."

        # Inside a shared block the claim has to be narrower: a group including
        # the block from a file the cop never reads could still reference the
        # name, so the finding is scoped to what this block can be seen to do.
        MSG_IN_SHARED_GROUP = "`%<helper>s(:%<name>s)` is not referenced anywhere in this shared example group. " \
                              "Remove it or reference it in an example."
        DEF_MSG_IN_SHARED_GROUP = "`def %<name>s` is not referenced anywhere in this shared example group. " \
                                  "Remove it or reference it in an example."
        ANONYMOUS_SUBJECT_MSG_IN_SHARED_GROUP =
          "`%<helper>s` is not referenced anywhere in this shared example group. " \
          "Remove it or reference it in an example."

        # @rbs!
        #   type cache_key = [ Time, Integer ]
        #   type cache_entry = [ cache_key, SharedExampleRegistry::definition_mapping? ]

        # @rbs self.@external_definitions_cache: Hash[String, cache_entry]?

        # Process-wide cache of the external files' definition maps, keyed by
        # absolute path to `[[mtime, size], definitions | nil]`. It lives on the
        # class because RuboCop builds a fresh cop instance per inspected file,
        # so a support file shared by many specs is scanned once per process,
        # not once per spec.
        def self.external_definitions_cache #: Hash[String, cache_entry]
          @external_definitions_cache ||= {}
        end

        def on_new_investigation #: void
          super
          @stack = []
          @builder = ScopeBuilder.new(
            processed_source.file_path,
            SharedExampleRegistry.new(processed_source.ast, external_definitions)
          )
        end

        # The pre-loaded files' digest for RuboCop's result-cache key, which
        # otherwise covers no project file but the inspected one. `nil` when
        # nothing is pre-loaded. Asked for once per configuration, so reading
        # each file here is cheap.
        def external_dependency_checksum #: String?
          paths = external_paths
          return nil if paths.empty?

          Digest::SHA1.hexdigest(paths.map { file_signature(_1) }.join("\n"))
        end

        # RuboCop visits nested groups on their own `on_block`, so we never
        # descend manually. On the way in the ancestors are exactly the scopes
        # already on the stack, so resolve this group's references against them
        # now; descendant groups resolve against this one later, as they are
        # entered.
        #
        # @rbs node: RuboCop::AST::Node
        def on_block(node) #: void
          return unless builder.spec_group?(node)

          scope = builder.build_from(node)
          mark(scope)
          stack.push(scope)
        end

        # A group's `let`s know whether they were referenced once its whole
        # subtree has been entered, which is complete by the time it is left.
        #
        # @rbs node: RuboCop::AST::Node
        def after_block(node) #: void
          return unless builder.spec_group?(node)

          scope = stack.pop
          return unless scope

          shared_groups = [scope, *stack].select(&:shared?)
          report(scope, in_shared_group: shared_groups.any?) if reportable_in?(shared_groups)
        end

        private

        attr_reader :stack #: Array[Scope]
        attr_reader :builder #: ScopeBuilder

        # The `SharedExamplePaths` files' definition maps to hand the registry,
        # excluding the file under investigation so it is never indexed twice.
        def external_definitions #: Array[SharedExampleRegistry::definition_mapping]
          path = processed_source.file_path
          current = File.expand_path(path) if path
          external_paths.reject { _1 == current }.filter_map { definitions_for(_1) }
        end

        # The absolute paths the `SharedExamplePaths` patterns expand to, in a
        # stable order. Not cached on the class: a `--server` process outlives a
        # run, so a cached expansion would go on ignoring later additions.
        def external_paths #: Array[String]
          patterns = Array(cop_config["SharedExamplePaths"])
          return [] if patterns.empty?

          base = config.base_dir_for_path_parameters
          patterns
            .flat_map { Dir.glob(File.expand_path(_1, base)) }
            .map { File.expand_path(_1) }
            .uniq
            .sort
        end

        # `path`'s identity for the result-cache digest. Content rather than
        # mtime, which git does not preserve: keying on it would let a checkout
        # discard a persisted cache wholesale. An unreadable path still gets a
        # stable entry rather than breaking the run.
        #
        # @rbs path: String
        def file_signature(path) #: String
          "#{path}:#{Digest::SHA1.file(path).hexdigest}"
        rescue SystemCallError
          "#{path}:"
        end

        # The cached definition map for one external file, or `nil` when it
        # cannot be read or parsed — in which case the cop stays conservative
        # rather than crashing the run.
        #
        # @rbs path: String
        def definitions_for(path) #: SharedExampleRegistry::definition_mapping?
          stat = File.stat(path)
          key = [stat.mtime, stat.size] #: cache_key
          cache = self.class.external_definitions_cache
          cached = cache[path]
          return cached.last if cached && cached.first == key

          definitions = build_definitions_for(path)
          cache[path] = [key, definitions]
          definitions
        rescue SystemCallError
          nil
        end

        # @rbs path: String
        def build_definitions_for(path) #: SharedExampleRegistry::definition_mapping?
          ast = RuboCop::AST::ProcessedSource.from_file(path, target_ruby_version).ast
          ast && SharedExampleRegistry.new(ast).local_definitions
        rescue RuboCop::Error, SystemCallError
          nil
        end

        # Resolve `scope`'s references against the enclosing groups (the scopes
        # currently on the stack) and mark every definition they reach.
        #
        # @rbs scope: Scope
        def mark(scope) #: void
          ancestors = stack
          mark_upward(scope, ancestors)
          mark_downward(scope, ancestors)
          mark_referenced_all(scope, ancestors) if scope.inclusion
          mark_referenced_all(scope, ancestors) if ignore_helper_spec?(scope, ancestors)
        end

        # A reference made in this group, whether in an example or a helper body,
        # reaches a `let` defined here or in an enclosing group.
        #
        # @rbs scope: Scope
        # @rbs ancestors: Array[Scope]
        def mark_upward(scope, ancestors) #: void
          (scope.refs | scope.refs_in_example).each do |name|
            scope.mark_referenced(name)
            ancestors.each { _1.mark_referenced(name) }
          end
        end

        # A helper body in an enclosing group can reference a `let` defined here,
        # since it runs in the example's scope.
        #
        # @rbs scope: Scope
        # @rbs ancestors: Array[Scope]
        def mark_downward(scope, ancestors) #: void
          scope.defined_names.each do |name|
            scope.mark_referenced(name) if ancestors.any? { _1.refs.include?(name) }
          end
        end

        # A helper spec's auto-included module lives in another file and may
        # reference any `let` in scope, so every definition is treated as
        # referenced unless `CheckHelperSpecs` opts in. This judgement is
        # independent of shared inclusions.
        #
        # @rbs scope: Scope
        # @rbs ancestors: Array[Scope]
        def ignore_helper_spec?(scope, ancestors) #: bool
          return false if cop_config["CheckHelperSpecs"]

          helper_spec?(scope, ancestors)
        end

        # The effective `type:` is the innermost one in the group's ancestry
        # (each scope already carries its explicit type, or `:helper` inferred
        # from a `spec/helpers` location).
        #
        # @rbs scope: Scope
        # @rbs ancestors: Array[Scope]
        def helper_spec?(scope, ancestors) #: bool
          [scope, *ancestors].filter_map(&:type).first == :helper
        end

        # Treat every `let` visible in `scope` (its own and its ancestors') as
        # referenced. Used where references can't be fully seen from this file:
        # a shared inclusion, or a helper spec's auto-included module.
        #
        # @rbs scope: Scope
        # @rbs ancestors: Array[Scope]
        def mark_referenced_all(scope, ancestors) #: void
          [scope, *ancestors].each do |group|
            group.defined_names.each { group.mark_referenced(_1) }
          end
        end

        # Whether a group enclosed by `shared_groups` (the shared blocks among it
        # and its ancestors, in no particular order) can be judged from this
        # file: only when every one of them carries examples. A shared block
        # without them is a provider, existing to inject its `let`s into
        # whichever group writes `include_context`, so a `let` it never
        # references itself is exactly what it is for, not dead code.
        #
        # `CheckSharedExamples: false` puts every shared block — and every group
        # nested in one — off limits instead, since the groups that include the
        # block may live in files the cop never reads.
        #
        # @rbs shared_groups: Array[Scope]
        def reportable_in?(shared_groups) #: bool
          return true if shared_groups.empty?
          return false unless cop_config["CheckSharedExamples"]

          shared_groups.all?(&:carries_examples?)
        end

        # @rbs scope: Scope
        # @rbs in_shared_group: bool
        def report(scope, in_shared_group:) #: void
          scope.unreferenced_defs.each do |definition|
            next if definition.bang? && !cop_config["CheckLetBang"]
            next if definition.subject? && !cop_config["CheckSubject"]

            add_offense_for(definition, in_shared_group: in_shared_group)
          end
        end

        # @rbs definition: Scope::Definition
        # @rbs in_shared_group: bool
        def add_offense_for(definition, in_shared_group:) #: void
          node = definition.node #: untyped
          message = message_for(definition, in_shared_group: in_shared_group)
          highlight =
            if definition.def_helper?
              node.loc.keyword.join(node.loc.name)
            else
              node.block_type? ? node.send_node : node
            end
          add_offense(highlight, message: message) do |corrector|
            corrector.remove(
              range_by_whole_lines(node.source_range, include_final_newline: true)
            )
          end
        end

        # @rbs definition: Scope::Definition
        # @rbs in_shared_group: bool
        def message_for(definition, in_shared_group:) #: String
          helper = definition.helper
          name = definition.name
          if definition.def_helper?
            format(in_shared_group ? DEF_MSG_IN_SHARED_GROUP : DEF_MSG, name: name)
          elsif definition.anonymous?
            format(in_shared_group ? ANONYMOUS_SUBJECT_MSG_IN_SHARED_GROUP : ANONYMOUS_SUBJECT_MSG, helper: helper)
          else
            format(in_shared_group ? MSG_IN_SHARED_GROUP : MSG, helper: helper, name: name)
          end
        end
      end
    end
  end
end
