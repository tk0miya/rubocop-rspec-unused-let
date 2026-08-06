# frozen_string_literal: true

RSpec.describe RuboCop::Cop::RSpec::UnusedLet::ScopeBuilder do
  include_context "with UnusedLet AST helpers"

  describe "#build_from" do
    subject { described_class.new(spec_filename, registry).build_from(group_named(root, "target")) }

    # Build the registry from the same parse the group comes from, so node
    # identity lines up when an inclusion is resolved.
    let(:root) { parse(source, ruby_version) }
    let(:ruby_version) { RUBY_VERSION.to_f }
    let(:spec_filename) { nil }
    let(:registry) { RuboCop::Cop::RSpec::UnusedLet::SharedExampleRegistry.new(root) }

    context "when the group is a describe block" do
      let(:source) { <<~RUBY }
        describe "target" do
        end
      RUBY

      it "reports its kind as :example" do
        expect(subject.kind).to eq(:example)
      end
    end

    context "when the group is a shared_examples block" do
      let(:source) { <<~RUBY }
        shared_examples "target" do
        end
      RUBY

      it "reports its kind as :shared" do
        expect(subject.kind).to eq(:shared)
      end
    end

    context "when the group carries an example" do
      let(:source) { <<~RUBY }
        shared_examples "target" do
          it { expect(value).to eq(1) }
        end
      RUBY

      it "reports the Scope as carrying examples" do
        expect(subject.carries_examples?).to be(true)
      end
    end

    context "when the group carries no example" do
      let(:source) { <<~RUBY }
        shared_examples "target" do
          let(:value) { 1 }
        end
      RUBY

      it "reports the Scope as carrying none" do
        expect(subject.carries_examples?).to be(false)
      end
    end

    context "with `let` and `let!` definitions" do
      let(:source) { <<~RUBY }
        describe "target" do
          let(:value) { 1 }
          let!(:widget) { 2 }
        end
      RUBY

      it "records each definition with its helper" do
        expect(subject.defs.map { [_1.helper, _1.name] }).to contain_exactly(%i[let value], %i[let! widget])
      end
    end

    context "with a named subject" do
      let(:source) { <<~RUBY }
        describe "target" do
          subject(:widget) { described_class.new }
        end
      RUBY

      it "records it under its own name and the implicit `subject`" do
        expect(subject.defs).to contain_exactly(
          have_attributes(helper: :subject, name: :widget, names: %i[widget subject])
        )
      end
    end

    context "with a string-named subject" do
      let(:source) { <<~RUBY }
        describe "target" do
          subject("widget") { described_class.new }
        end
      RUBY

      it "normalizes the name to a symbol" do
        expect(subject.defs.map(&:name)).to contain_exactly(:widget)
      end
    end

    context "with an anonymous subject" do
      let(:source) { <<~RUBY }
        describe "target" do
          subject { described_class.new }
        end
      RUBY

      it "records it namelessly and does not read its head call as a reference" do
        expect(subject.defs).to contain_exactly(
          have_attributes(helper: :subject, name: nil, names: [:subject])
        )
        expect(subject.refs).not_to include(:subject)
      end
    end

    context "with a `subject!`" do
      let(:source) { <<~RUBY }
        describe "target" do
          subject!(:widget) { create(:widget) }
        end
      RUBY

      it "records its helper" do
        expect(subject.defs).to contain_exactly(have_attributes(helper: :subject!, name: :widget))
      end
    end

    %w[is_expected are_expected should should_not its].each do |one_liner|
      context "when an example uses `#{one_liner}`" do
        let(:source) { <<~RUBY }
          describe "target" do
            it { #{one_liner} }
          end
        RUBY

        it "records a reference to the implicit `subject`" do
          expect(subject.refs_in_example).to include(:subject)
        end
      end
    end

    context "with a string-named `let`" do
      let(:source) { <<~RUBY }
        describe "target" do
          let("value") { 1 }
        end
      RUBY

      it "normalizes the name to a symbol" do
        expect(subject.defs.map(&:name)).to contain_exactly(:value)
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

    context "with a `def` helper at the group's level" do
      let(:source) { <<~RUBY }
        describe "target" do
          def call
            1
          end
        end
      RUBY

      it "records it, the method becoming one on the group's example class" do
        expect(subject.defs).to contain_exactly(have_attributes(helper: :def, name: :call))
      end
    end

    context "with a `def` inside an anonymous class a `let` builds" do
      let(:source) { <<~RUBY }
        describe "target" do
          let(:klass) do
            Class.new do
              def call
                1
              end
            end
          end
        end
      RUBY

      it "records only the `let`, the method belonging to the inner definee" do
        expect(subject.defs).to contain_exactly(have_attributes(helper: :let, name: :klass))
      end
    end

    context "with a `def` inside a nested group" do
      let(:source) { <<~RUBY }
        describe "target" do
          context "nested" do
            def call
              1
            end
          end
        end
      RUBY

      it "leaves the definition to the nested group's own scope" do
        expect(subject.defs).to be_empty
      end
    end

    context "when the name is called directly in an example" do
      let(:source) { <<~RUBY }
        describe "target" do
          it { expect(value).to eq(1) }
        end
      RUBY

      it "records it as an example reference" do
        expect(subject.refs_in_example).to include(:value)
      end
    end

    %i[send public_send __send__ method respond_to?].each do |dispatch|
      context "when the name is dispatched through #{dispatch} with a symbol" do
        let(:source) { <<~RUBY }
          describe "target" do
            it { #{dispatch}(:value) }
          end
        RUBY

        it "records it as an example reference" do
          expect(subject.refs_in_example).to include(:value)
        end
      end
    end

    context "when the name is dispatched with a string argument" do
      let(:source) { <<~RUBY }
        describe "target" do
          it { send("value") }
        end
      RUBY

      it "records it as an example reference" do
        expect(subject.refs_in_example).to include(:value)
      end
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
        expect(subject.refs_in_example).not_to include(:value)
      end
    end

    context "when an example calls `subject` directly" do
      let(:source) { <<~RUBY }
        describe "target" do
          subject { described_class.new }

          it { expect(subject).to be_valid }
        end
      RUBY

      it "records it as an example reference" do
        expect(subject.refs_in_example).to include(:subject)
      end
    end

    # No declaration here, so the hook is the only possible source of the reference.
    context "when a hook calls `subject` directly" do
      let(:source) { <<~RUBY }
        describe "target" do
          before { subject }
        end
      RUBY

      it "records it as a helper reference" do
        expect(subject.refs).to include(:subject)
      end
    end

    context "when a hook body references the name" do
      let(:source) { <<~RUBY }
        describe "target" do
          before { value }
        end
      RUBY

      it "records it as a helper reference" do
        expect(subject.refs).to include(:value)
      end
    end

    context "when a hook body dispatches the name dynamically" do
      let(:source) { <<~RUBY }
        describe "target" do
          before { send(:value) }
        end
      RUBY

      it "records it as a helper reference" do
        expect(subject.refs).to include(:value)
      end
    end

    context "when a `let` body references the name" do
      let(:source) { <<~RUBY }
        describe "target" do
          let(:wrapper) { [value] }
        end
      RUBY

      it "records it as a helper reference" do
        expect(subject.refs).to include(:value)
      end
    end

    context "when a `subject` body references the name" do
      let(:source) { <<~RUBY }
        describe "target" do
          subject { value + 1 }
        end
      RUBY

      it "records it as a helper reference" do
        expect(subject.refs).to include(:value)
      end
    end

    context "when a `def` helper at the group's level references the name" do
      let(:source) { <<~RUBY }
        describe "target" do
          def call_helper
            value
          end
        end
      RUBY

      it "records it as a helper reference" do
        expect(subject.refs).to include(:value)
      end
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
        expect(subject.refs).not_to include(:value)
      end
    end

    context "when a `def` inside a block the cop cannot name as RSpec's own references the name" do
      let(:source) { <<~RUBY }
        describe "target" do
          with_model :Blog do
            model do
              def call_helper
                value
              end
            end
          end
        end
      RUBY

      it "still records it as a helper reference, in case the block runs in the example's scope" do
        expect(subject.refs).to include(:value)
      end
    end

    context "when a `def` inside a `class` body written in the group references the name" do
      let(:source) { <<~RUBY }
        describe "target" do
          class Dummy
            def call_helper
              value
            end
          end
        end
      RUBY

      it "leaves the reference to the class body, which never runs in the example's scope" do
        expect(subject.refs).not_to include(:value)
      end
    end

    %w[it_behaves_like it_should_behave_like include_context include_examples].each do |inclusion|
      context "when the group includes a shared example via #{inclusion}" do
        let(:source) { <<~RUBY }
          describe "target" do
            #{inclusion} "something"
          end
        RUBY

        it "marks the scope as carrying an inclusion" do
          expect(subject.inclusion).to be(true)
        end
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

    context "when the included block is defined in the same file" do
      let(:source) { <<~RUBY }
        describe "target" do
          it_behaves_like "a thing"
        end

        shared_examples "a thing" do
          it { expect(value).to eq(1) }
        end
      RUBY

      it "records the block's free references and stays out of the conservative fallback" do
        expect(subject.refs_in_example).to include(:value)
        expect(subject.inclusion).to be(false)
      end
    end

    context "when the included block is not defined in the file" do
      let(:source) { <<~RUBY }
        describe "target" do
          it_behaves_like "a thing"
        end
      RUBY

      it "falls back to the conservative inclusion flag" do
        expect(subject.inclusion).to be(true)
      end
    end

    context "when the group carries `type: :validator`" do
      let(:source) { <<~RUBY }
        describe "target", type: :validator do
        end
      RUBY

      it "records the known gem's names as example and helper references" do
        expect(subject.refs_in_example).to include(:value, :attribute_names, :options)
        expect(subject.refs).to include(:value, :attribute_names, :options)
      end
    end

    context "when the group carries an unknown type" do
      let(:source) { <<~RUBY }
        describe "target", type: :model do
        end
      RUBY

      it "injects nothing" do
        expect(subject.refs_in_example).not_to include(:value)
      end
    end

    context "without `type:` metadata" do
      let(:source) { <<~RUBY }
        describe "target" do
        end
      RUBY

      it "injects nothing" do
        expect(subject.refs_in_example).not_to include(:value)
      end
    end

    context "when the spec file sits under `spec/helpers`" do
      let(:spec_filename) { "spec/helpers/my_helper_spec.rb" }

      context "when the group carries no explicit `type:`" do
        let(:source) { <<~RUBY }
          describe "target" do
          end
        RUBY

        it "infers `type: :helper` from the location, as rspec-rails does" do
          expect(subject.type).to eq(:helper)
        end
      end

      context "when the group carries an explicit `type:`" do
        let(:source) { <<~RUBY }
          describe "target", type: :model do
          end
        RUBY

        it "prefers the explicit type over the inferred one" do
          expect(subject.type).to eq(:model)
        end
      end
    end

    context "when the spec file sits outside `spec/helpers`" do
      let(:spec_filename) { "spec/models/my_model_spec.rb" }
      let(:source) { <<~RUBY }
        describe "target" do
        end
      RUBY

      it "infers no type" do
        expect(subject.type).to be_nil
      end
    end
  end
end
