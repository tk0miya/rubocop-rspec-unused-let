# frozen_string_literal: true

RSpec.describe RuboCop::Cop::RSpec::UnusedLet::Scope do
  def build_scope(kind: :example)
    described_class.new(node: nil, kind: kind)
  end

  let(:def_node) { :a_let_node }

  describe "#unreferenced_defs" do
    subject { scope.unreferenced_defs }

    let(:scope) { build_scope }

    before { scope.add_definition(:let, :value, def_node) }

    context "when the definition is never marked referenced" do
      it { is_expected.to contain_exactly([:let, :value, def_node]) }
    end

    context "when the scope is a shared group" do
      let(:scope) { build_scope(kind: :shared) }

      it { is_expected.to be_empty }
    end

    context "when the name has been marked referenced" do
      before { scope.mark_referenced(:value) }

      it { is_expected.to be_empty }
    end

    context "when only a different name has been marked referenced" do
      before { scope.mark_referenced(:other) }

      it { is_expected.to contain_exactly([:let, :value, def_node]) }
    end
  end

  describe "#defined_names" do
    subject { scope.defined_names }

    let(:scope) { build_scope }

    before do
      scope.add_definition(:let, :first, :first_node)
      scope.add_definition(:let!, :second, :second_node)
    end

    it { is_expected.to eq(%i[first second]) }
  end

  describe "#example?" do
    it { expect(build_scope(kind: :example).example?).to be(true) }
    it { expect(build_scope(kind: :shared).example?).to be(false) }
  end
end
