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

    # A non-match returns the node matcher's `nil` rather than `false`, so these
    # assert falsiness rather than the exact value.
    context "when the node opens no definee of its own" do
      context "with a plain block" do
        let(:source) { <<~RUBY }
          [1, 2].each do |n|
            n
          end
        RUBY

        it { is_expected.to be_falsey }
      end

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

      context "with a builder call carrying no block" do
        let(:source) { <<~RUBY }
          Class.new(StandardError)
        RUBY

        it { is_expected.to be_falsey }
      end

      context "with a same-named call on another receiver" do
        let(:source) { <<~RUBY }
          collection.new { 1 }
        RUBY

        it { is_expected.to be_falsey }
      end

      context "with a receiverless `instance_eval`" do
        let(:source) { <<~RUBY }
          instance_eval do
            def call
              1
            end
          end
        RUBY

        it { is_expected.to be_falsey }
      end
    end
  end
end
