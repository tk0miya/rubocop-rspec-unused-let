# frozen_string_literal: true

RSpec.describe RuboCop::Cop::RSpec::UnusedLet::SharedExampleResolver do
  include_context "with UnusedLet AST helpers"

  describe "#referenced_names" do
    subject { described_class.new(ast: parse(source)).referenced_names(inclusion) }

    # The `it_behaves_like` send node introduced with the given name argument.
    def inclusion_for(name)
      parse(source).each_descendant(:send).find do |node|
        arg = node.first_argument
        node.method_name == :it_behaves_like && arg&.type?(:sym, :str) && arg.value == name
      end
    end

    context "when the shared block references names" do
      let(:source) { <<~RUBY }
        RSpec.shared_examples "a thing" do
          it { expect(value).to eq(1) }
          before { send(:other) }
        end

        RSpec.describe Foo do
          it_behaves_like "a thing"
        end
      RUBY
      let(:inclusion) { inclusion_for("a thing") }

      it { is_expected.to include(:value, :other) }
    end

    context "when the shared block references nothing relevant" do
      let(:source) { <<~RUBY }
        RSpec.shared_examples "a thing" do
          it { expect(1).to eq(1) }
        end

        RSpec.describe Foo do
          it_behaves_like "a thing"
        end
      RUBY
      let(:inclusion) { inclusion_for("a thing") }

      it { is_expected.not_to include(:value) }
    end

    context "when the shared block includes another shared block" do
      let(:source) { <<~RUBY }
        RSpec.shared_examples "inner" do
          it { expect(deep).to eq(1) }
        end

        RSpec.shared_examples "outer" do
          it_behaves_like "inner"
        end

        RSpec.describe Foo do
          it_behaves_like "outer"
        end
      RUBY
      let(:inclusion) { inclusion_for("outer") }

      it { is_expected.to include(:deep) }
    end

    context "when the inclusion name is not a literal" do
      let(:source) { <<~RUBY }
        RSpec.describe Foo do
          it_behaves_like some_variable
        end
      RUBY
      let(:inclusion) do
        parse(source).each_descendant(:send).find { _1.method_name == :it_behaves_like }
      end

      it { is_expected.to be_nil }
    end

    context "when no definition matches the name" do
      let(:source) { <<~RUBY }
        RSpec.describe Foo do
          it_behaves_like "missing"
        end
      RUBY
      let(:inclusion) { inclusion_for("missing") }

      it { is_expected.to be_nil }
    end

    context "when the name is defined more than once" do
      let(:source) { <<~RUBY }
        RSpec.shared_examples "a thing" do
          it { expect(1).to eq(1) }
        end

        RSpec.shared_examples "a thing" do
          it { expect(2).to eq(2) }
        end

        RSpec.describe Foo do
          it_behaves_like "a thing"
        end
      RUBY
      let(:inclusion) { inclusion_for("a thing") }

      it { is_expected.to be_nil }
    end

    context "when a transitively included name is unknown" do
      let(:source) { <<~RUBY }
        RSpec.shared_examples "outer" do
          it_behaves_like "missing"
        end

        RSpec.describe Foo do
          it_behaves_like "outer"
        end
      RUBY
      let(:inclusion) { inclusion_for("outer") }

      it { is_expected.to be_nil }
    end

    context "when the shared blocks form a cycle" do
      let(:source) { <<~RUBY }
        RSpec.shared_examples "ping" do
          it_behaves_like "pong"
        end

        RSpec.shared_examples "pong" do
          it_behaves_like "ping"
        end

        RSpec.describe Foo do
          it_behaves_like "ping"
        end
      RUBY
      let(:inclusion) { inclusion_for("ping") }

      it { is_expected.to be_nil } # bails rather than looping
    end
  end
end
