# frozen_string_literal: true

RSpec.describe RuboCop::Cop::RSpec::UnusedLet::SharedExampleRegistry do
  include_context "with UnusedLet AST helpers"

  # The shared-example inclusion nodes (`it_behaves_like`, ...) in `root`, in
  # document order, so a spec can resolve a specific inclusion by position.
  def inclusion_nodes(root)
    [root, *root.each_descendant(:send)].select do |node|
      node.send_type? &&
        %i[it_behaves_like it_should_behave_like include_examples include_context].include?(node.method_name)
    end
  end

  describe "#resolve" do
    subject { registry.resolve(name, inclusion_nodes(root).fetch(index)) }

    # Build the registry and locate the inclusion from the *same* parse, so node
    # identity (scope ancestry, owner) lines up between the two.
    let(:root) { parse(source) }
    let(:registry) { described_class.new(root) }
    let(:name) { "a thing" }
    let(:index) { 0 }

    context "when the shared block references a free name" do
      let(:source) { <<~RUBY }
        RSpec.shared_examples "a thing" do
          it { expect(value).to eq(1) }
        end

        RSpec.describe Foo do
          it_behaves_like "a thing"
        end
      RUBY

      it { is_expected.to include(:value) }
    end

    context "when the name is dispatched dynamically" do
      let(:source) { <<~RUBY }
        RSpec.shared_examples "a thing" do
          it { send(:value) }
        end

        RSpec.describe Foo do
          it_behaves_like "a thing"
        end
      RUBY

      it { is_expected.to include(:value) }
    end

    context "when the shared block defines the name itself" do
      let(:source) { <<~RUBY }
        RSpec.shared_examples "a thing" do
          let(:value) { 1 }

          it { expect(value).to eq(1) }
        end

        RSpec.describe Foo do
          it_behaves_like "a thing"
        end
      RUBY

      it { is_expected.not_to include(:value) }
    end

    context "when a nested group inside the shared block references names" do
      let(:source) { <<~RUBY }
        RSpec.shared_examples "a thing" do
          context "nested" do
            it { is_expected.to contain_exactly(value1, value2) }
          end
        end

        RSpec.describe Foo do
          it_behaves_like "a thing"
        end
      RUBY

      it { is_expected.to include(:value1, :value2) }
    end

    context "when a nested group inside the shared block defines the name" do
      let(:source) { <<~RUBY }
        RSpec.shared_examples "a thing" do
          context "nested" do
            let(:value) { 1 }

            it { expect(value).to eq(1) }
          end
        end

        RSpec.describe Foo do
          it_behaves_like "a thing"
        end
      RUBY

      it { is_expected.not_to include(:value) }
    end

    context "with a symbol-named shared block" do
      let(:name) { :a_thing }
      let(:source) { <<~RUBY }
        RSpec.shared_examples :a_thing do
          it { expect(value).to eq(1) }
        end

        RSpec.describe Foo do
          it_behaves_like :a_thing
        end
      RUBY

      it { is_expected.to include(:value) }
    end

    context "when the shared block is defined with a bare receiver" do
      let(:source) { <<~RUBY }
        shared_context "a thing" do
          it { expect(value).to eq(1) }
        end

        describe Foo do
          it_behaves_like "a thing"
        end
      RUBY

      it { is_expected.to include(:value) }
    end

    context "when the shared block includes another resolvable block" do
      let(:source) { <<~RUBY }
        RSpec.shared_examples "a thing" do
          include_examples "inner"
        end

        RSpec.shared_examples "inner" do
          it { expect(value).to eq(1) }
        end

        RSpec.describe Foo do
          it_behaves_like "a thing"
        end
      RUBY

      it "folds in the nested block's free references" do
        expect(subject).to include(:value)
      end
    end

    context "when the nested block defines the name the outer block references" do
      let(:source) { <<~RUBY }
        RSpec.shared_examples "a thing" do
          let(:value) { 1 }

          include_examples "inner"
        end

        RSpec.shared_examples "inner" do
          it { expect(value).to eq(1) }
        end

        RSpec.describe Foo do
          it_behaves_like "a thing"
        end
      RUBY

      it { is_expected.not_to include(:value) }
    end

    context "when an inner definition shadows an outer one of the same name" do
      let(:source) { <<~RUBY }
        RSpec.shared_examples "a thing" do
          it { expect(outer_ref).to eq(1) }
        end

        RSpec.describe Foo do
          context "inner" do
            shared_examples "a thing" do
              it { expect(inner_ref).to eq(1) }
            end

            it_behaves_like "a thing"
          end

          it_behaves_like "a thing"
        end
      RUBY

      # inclusion_nodes are in document order: the inner one comes first.
      context "when resolving the inner inclusion" do
        let(:index) { 0 }

        it "resolves to the nearest definition, shadowing the outer one" do
          expect(subject).to include(:inner_ref)
          expect(subject).not_to include(:outer_ref)
        end
      end

      context "when resolving the outer inclusion" do
        let(:index) { 1 }

        it "resolves to the top-level definition, not the inner one" do
          expect(subject).to include(:outer_ref)
          expect(subject).not_to include(:inner_ref)
        end
      end
    end

    context "when the name is redefined in the same scope" do
      let(:source) { <<~RUBY }
        RSpec.shared_examples "a thing" do
          it { expect(old_ref).to eq(1) }
        end

        RSpec.shared_examples "a thing" do
          it { expect(new_ref).to eq(1) }
        end

        RSpec.describe Foo do
          it_behaves_like "a thing"
        end
      RUBY

      it "uses the last definition, as RSpec warns and keeps the latest" do
        expect(subject).to include(:new_ref)
        expect(subject).not_to include(:old_ref)
      end
    end

    context "when the definition lives in a sibling group" do
      let(:source) { <<~RUBY }
        RSpec.describe Foo do
          shared_examples "a thing" do
            it { expect(value).to eq(1) }
          end
        end

        RSpec.describe Bar do
          it_behaves_like "a thing"
        end
      RUBY

      it { is_expected.to be_nil }
    end

    context "when the name is not defined in the file" do
      let(:source) { <<~RUBY }
        RSpec.describe Foo do
          it_behaves_like "a thing"
        end
      RUBY

      it { is_expected.to be_nil }
    end

    context "when the shared block includes an unknown block" do
      let(:source) { <<~RUBY }
        RSpec.shared_examples "a thing" do
          include_examples "missing"
        end

        RSpec.describe Foo do
          it_behaves_like "a thing"
        end
      RUBY

      it { is_expected.to be_nil }
    end

    context "when the shared block includes a block under a dynamic name" do
      let(:source) { <<~RUBY }
        RSpec.shared_examples "a thing" do
          include_examples SHARED
        end

        RSpec.describe Foo do
          it_behaves_like "a thing"
        end
      RUBY

      it { is_expected.to be_nil }
    end

    context "when two shared blocks include each other" do
      let(:source) { <<~RUBY }
        RSpec.shared_examples "a thing" do
          include_examples "other"
        end

        RSpec.shared_examples "other" do
          include_examples "a thing"
        end

        RSpec.describe Foo do
          it_behaves_like "a thing"
        end
      RUBY

      it { is_expected.to be_nil }
    end

    context "without any indexed AST" do
      let(:registry) { described_class.new(nil) }
      let(:source) { <<~RUBY }
        RSpec.describe Foo do
          it_behaves_like "a thing"
        end
      RUBY

      it { is_expected.to be_nil }
    end
  end
end
