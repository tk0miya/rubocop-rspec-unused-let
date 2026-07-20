# frozen_string_literal: true

RSpec.describe RuboCop::Cop::RSpec::UnusedLet::ScopeBuilder do
  include_context "with UnusedLet AST helpers"

  describe "#build_from" do
    subject { described_class.new.build_from(group_named(parse(source), "target")) }

    describe "kind" do
      context "when the group is a describe block" do
        let(:source) { <<~RUBY }
          describe "target" do
          end
        RUBY

        it { expect(subject.kind).to eq(:example) }
      end

      context "when the group is a shared_examples block" do
        let(:source) { <<~RUBY }
          shared_examples "target" do
          end
        RUBY

        it { expect(subject.kind).to eq(:shared) }
      end
    end

    describe "defs" do
      context "with `let` and `let!` definitions" do
        let(:source) { <<~RUBY }
          describe "target" do
            let(:value) { 1 }
            let!(:widget) { 2 }
          end
        RUBY

        it "records each definition with its helper" do
          expect(subject.defs).to contain_exactly([:let, :value, anything], [:let!, :widget, anything])
        end
      end

      context "with a string-named `let`" do
        let(:source) { <<~RUBY }
          describe "target" do
            let("value") { 1 }
          end
        RUBY

        it "normalizes the name to a symbol" do
          expect(subject.defs).to contain_exactly([:let, :value, anything])
        end
      end

      context "with a `let` defined in a nested group" do
        let(:source) { <<~RUBY }
          describe "target" do
            context "nested" do
              let(:value) { 1 }
            end
          end
        RUBY

        it "leaves the definition to the nested group's own scope" do
          expect(subject.defs).to be_empty
        end
      end
    end

    describe "refs" do
      context "when the name is called directly in an example" do
        let(:source) { <<~RUBY }
          describe "target" do
            it { expect(value).to eq(1) }
          end
        RUBY

        it { expect(subject.refs).to include(:value) }
      end

      %i[send public_send __send__ method respond_to?].each do |dispatch|
        context "when the name is dispatched through #{dispatch} with a symbol" do
          let(:source) { <<~RUBY }
            describe "target" do
              it { #{dispatch}(:value) }
            end
          RUBY

          it { expect(subject.refs).to include(:value) }
        end
      end

      context "when the name is dispatched with a string argument" do
        let(:source) { <<~RUBY }
          describe "target" do
            it { send("value") }
          end
        RUBY

        it { expect(subject.refs).to include(:value) }
      end

      context "when the reference sits inside a nested group" do
        let(:source) { <<~RUBY }
          describe "target" do
            context "nested" do
              it { expect(value).to eq(1) }
            end
          end
        RUBY

        it "leaves the reference to the nested group's own scope" do
          expect(subject.refs).not_to include(:value)
        end
      end
    end

    describe "helper_refs" do
      context "when a hook body references the name" do
        let(:source) { <<~RUBY }
          describe "target" do
            before { value }
          end
        RUBY

        it { expect(subject.helper_refs).to include(:value) }
      end

      context "when a hook body dispatches the name dynamically" do
        let(:source) { <<~RUBY }
          describe "target" do
            before { send(:value) }
          end
        RUBY

        it { expect(subject.helper_refs).to include(:value) }
      end

      context "when a `let` body references the name" do
        let(:source) { <<~RUBY }
          describe "target" do
            let(:wrapper) { [value] }
          end
        RUBY

        it { expect(subject.helper_refs).to include(:value) }
      end

      context "when a `subject` body references the name" do
        let(:source) { <<~RUBY }
          describe "target" do
            subject { value + 1 }
          end
        RUBY

        it { expect(subject.helper_refs).to include(:value) }
      end

      context "when a `def` helper at the group's level references the name" do
        let(:source) { <<~RUBY }
          describe "target" do
            def call_helper
              value
            end
          end
        RUBY

        it { expect(subject.helper_refs).to include(:value) }
      end

      context "when the referencing `def` helper sits inside a nested group" do
        let(:source) { <<~RUBY }
          describe "target" do
            context "nested" do
              def call_helper
                value
              end
            end
          end
        RUBY

        it "leaves the reference to the nested group's own scope" do
          expect(subject.helper_refs).not_to include(:value)
        end
      end
    end

    describe "inclusion" do
      %w[it_behaves_like it_should_behave_like include_context include_examples].each do |inclusion|
        context "when the group includes a shared example via #{inclusion}" do
          let(:source) { <<~RUBY }
            describe "target" do
              #{inclusion} "something"
            end
          RUBY

          it { expect(subject.inclusion).to be(true) }
        end
      end

      context "when the inclusion sits inside a nested group" do
        let(:source) { <<~RUBY }
          describe "target" do
            context "nested" do
              it_behaves_like "something"
            end
          end
        RUBY

        it "leaves the inclusion to the nested group's own scope" do
          expect(subject.inclusion).to be(false)
        end
      end
    end

    describe "refs and helper_refs injected via `type:` metadata" do
      context "when the group carries `type: :validator`" do
        let(:source) { <<~RUBY }
          describe "target", type: :validator do
          end
        RUBY

        it "records the known gem's names as region and helper references" do
          expect(subject.refs).to include(:value, :attribute_names, :options)
          expect(subject.helper_refs).to include(:value, :attribute_names, :options)
        end
      end

      context "when the group carries an unknown type" do
        let(:source) { <<~RUBY }
          describe "target", type: :model do
          end
        RUBY

        it "injects nothing" do
          expect(subject.refs).not_to include(:value)
        end
      end

      context "without `type:` metadata" do
        let(:source) { <<~RUBY }
          describe "target" do
          end
        RUBY

        it "injects nothing" do
          expect(subject.refs).not_to include(:value)
        end
      end
    end
  end
end
