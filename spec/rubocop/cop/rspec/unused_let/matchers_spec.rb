# frozen_string_literal: true

RSpec.describe RuboCop::Cop::RSpec::UnusedLet::Matchers do
  include_context "with UnusedLet AST helpers"

  # The module is a mixin of node-pattern predicates, exercised here through a
  # bare includer rather than through one of the classes that use it.
  let(:matchers) { Class.new { include RuboCop::Cop::RSpec::UnusedLet::Matchers }.new }

  describe "#definee_scope?" do
    # Every source below parses to the node under test as its root.
    subject { matchers.definee_scope?(parse(source, ruby_version)) }

    let(:ruby_version) { RUBY_VERSION.to_f }

    context "when the scope is opened by a keyword" do
      ["def call", "def self.call", "class Dummy", "module Helpers", "class << self"].each do |opener|
        context "with `#{opener}`" do
          let(:source) { <<~RUBY }
            #{opener}
            end
          RUBY

          it { is_expected.to be(true) }
        end
      end
    end

    context "when the scope is opened by an anonymous class builder" do
      ["Class.new", "Module.new", "Struct.new(:value)", "Data.define(:value)", "::Class.new"].each do |builder|
        context "with `#{builder}`" do
          let(:source) { <<~RUBY }
            #{builder} do
              def call
                1
              end
            end
          RUBY

          it { is_expected.to be(true) }
        end
      end
    end

    context "when the scope is opened by a reopening block" do
      %w[class_eval module_eval instance_eval class_exec module_exec instance_exec].each do |reopener|
        context "with `#{reopener}`" do
          let(:source) { <<~RUBY }
            Dummy.#{reopener} do
              def call
                1
              end
            end
          RUBY

          it { is_expected.to be(true) }
        end
      end

      context "when the reopening block takes a parameter" do
        context "with a numbered parameter, a `numblock` node" do
          let(:source) { <<~RUBY }
            Dummy.class_eval do
              def call
                1
              end

              _1.freeze
            end
          RUBY

          it { is_expected.to be(true) }
        end

        context "with the implicit `it` parameter, an `itblock` node" do
          let(:ruby_version) { 3.4 }
          let(:source) { <<~RUBY }
            Dummy.class_eval do
              def call
                1
              end

              it.freeze
            end
          RUBY

          it { is_expected.to be(true) }
        end
      end
    end

    context "when the scope is opened by a block the cop cannot name as RSpec's own" do
      context "with a plain iteration block" do
        let(:source) { <<~RUBY }
          [1, 2].each do |n|
            def call
              n
            end
          end
        RUBY

        it { is_expected.to be(true) }
      end

      context "with a same-named call on another receiver" do
        let(:source) { <<~RUBY }
          collection.new { 1 }
        RUBY

        it { is_expected.to be(true) }
      end

      context "with a receiverless `instance_eval`" do
        let(:source) { <<~RUBY }
          instance_eval do
            def call
              1
            end
          end
        RUBY

        it { is_expected.to be(true) }
      end

      context "with rspec-rails' `controller` block" do
        let(:source) { <<~RUBY }
          controller do
            def index
              1
            end
          end
        RUBY

        it { is_expected.to be(true) }
      end
    end

    # A non-match returns the node matcher's `nil` rather than `false`, so these
    # assert falsiness rather than the exact value.
    context "when the node opens no definee of its own" do
      context "with an example group's block" do
        let(:source) { <<~RUBY }
          describe Foo do
            it { expect(true).to be(true) }
          end
        RUBY

        it { is_expected.to be_falsey }
      end

      context "with a `let` block" do
        let(:source) { <<~RUBY }
          let(:value) { 1 }
        RUBY

        it { is_expected.to be_falsey }
      end

      context "with a `subject` block" do
        let(:source) { <<~RUBY }
          subject { 1 }
        RUBY

        it { is_expected.to be_falsey }
      end

      context "with a hook block" do
        let(:source) { <<~RUBY }
          before do
            1
          end
        RUBY

        it { is_expected.to be_falsey }
      end

      context "with an example block" do
        let(:source) { <<~RUBY }
          it "does something" do
            1
          end
        RUBY

        it { is_expected.to be_falsey }
      end

      context "with an inclusion's customization block" do
        let(:source) { <<~RUBY }
          it_behaves_like "a thing" do
            1
          end
        RUBY

        it { is_expected.to be_falsey }
      end

      context "with a builder call carrying no block" do
        let(:source) { <<~RUBY }
          Class.new(StandardError)
        RUBY

        it { is_expected.to be_falsey }
      end
    end
  end

  describe "#carries_examples?" do
    # Every source below parses to the node under test as its root.
    subject { matchers.carries_examples?(parse(source, ruby_version)) }

    let(:ruby_version) { RUBY_VERSION.to_f }

    context "when a shared group holds an example" do
      let(:source) { <<~RUBY }
        shared_examples "target" do
          it { expect(value).to eq(1) }
        end
      RUBY

      it { is_expected.to be(true) }
    end

    context "when a shared group holds an example without a block" do
      let(:source) { <<~RUBY }
        shared_examples "target" do
          it "is pending"
        end
      RUBY

      it { is_expected.to be(true) }
    end

    context "when a shared group holds an example only in a nested group" do
      let(:source) { <<~RUBY }
        shared_examples "target" do
          context "nested" do
            it { expect(value).to eq(1) }
          end
        end
      RUBY

      it { is_expected.to be(true) }
    end

    context "when a shared group holds no example" do
      let(:source) { <<~RUBY }
        shared_examples "target" do
          let(:value) { 1 }

          before { setup }
        end
      RUBY

      it { is_expected.to be(false) }
    end

    %i[skip pending].each do |selector|
      context "when a shared group calls `#{selector}` at its own level" do
        let(:source) { <<~RUBY }
          shared_examples "target" do
            #{selector} "not now"
          end
        RUBY

        it "reports it as carrying examples, the call defining one" do
          expect(subject).to be(true)
        end
      end

      context "when a shared group only calls `#{selector}` from a hook" do
        let(:source) { <<~RUBY }
          shared_examples "target" do
            before { #{selector}("not now") }
          end
        RUBY

        it "reports it as carrying none, despite `#{selector}` being an example selector" do
          expect(subject).to be(false)
        end
      end

      context "when a shared group only calls `#{selector}` from a `def` helper" do
        let(:source) { <<~RUBY }
          shared_examples "target" do
            def bail_out
              #{selector}("not now")
            end
          end
        RUBY

        it { is_expected.to be(false) }
      end
    end

    context "when the only example is generated by a loop" do
      context "with a named parameter, a `block` node" do
        let(:source) { <<~RUBY }
          shared_examples "target" do
            [1, 2].each { |n| it(n.to_s) { expect(value).to eq(n) } }
          end
        RUBY

        it { is_expected.to be(false) }
      end

      context "with a numbered parameter, a `numblock` node" do
        let(:source) { <<~RUBY }
          shared_examples "target" do
            [1, 2].each { it(_1.to_s) { expect(value).to be_positive } }
          end
        RUBY

        it { is_expected.to be(false) }
      end

      # Pinned to 3.4, the version that first parses `it` as the parameter. `it`
      # names the block parameter here, so the example is declared with
      # `specify`.
      context "with the implicit `it` parameter, an `itblock` node" do
        let(:ruby_version) { 3.4 }
        let(:source) { <<~'RUBY' }
          shared_examples "target" do
            [1, 2].each { specify("case #{it}") { expect(value).to be_positive } }
          end
        RUBY

        it { is_expected.to be(false) }
      end
    end

    context "when the only example sits in a class body" do
      let(:source) { <<~RUBY }
        shared_examples "target" do
          class Dummy
            it "is not an example here"
          end
        end
      RUBY

      it { is_expected.to be(false) }
    end

    context "when the only example belongs to a nested shared group" do
      let(:source) { <<~RUBY }
        shared_examples "target" do
          shared_examples "inner" do
            it { expect(value).to eq(1) }
          end
        end
      RUBY

      it { is_expected.to be(false) }
    end
  end
end
