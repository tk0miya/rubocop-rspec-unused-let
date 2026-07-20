# frozen_string_literal: true

RSpec.describe RuboCop::Cop::RSpec::UnusedLet::Scope do
  def build_scope(kind: :example)
    described_class.new(node: nil, kind: kind)
  end

  let(:def_node) { :a_let_node }

  describe "#unreferenced_defs" do
    subject { scope.unreferenced_defs(ancestors) }

    let(:scope) { build_scope }
    let(:ancestors) { [] }

    before { scope.add_definition(:let, :value, def_node) }

    context "when the definition is never referenced" do
      it { is_expected.to contain_exactly([:let, :value, def_node]) }
    end

    context "when the scope is a shared group" do
      let(:scope) { build_scope(kind: :shared) }

      it { is_expected.to be_empty }
    end

    context "when the name is referenced in the subtree" do
      before { scope.add_reference(:value) }

      it { is_expected.to be_empty }
    end

    context "when only a different name is referenced" do
      before { scope.add_reference(:other) }

      it { is_expected.to contain_exactly([:let, :value, def_node]) }
    end

    context "when a shared inclusion sits in the scope itself" do
      before { scope.mark_inclusion }

      it { is_expected.to be_empty }
    end

    context "when an absorbed child brings a reference" do
      before do
        child = build_scope
        child.add_reference(:value)
        scope.absorb(child)
      end

      it { is_expected.to be_empty }
    end

    context "when an absorbed child brings a shared inclusion" do
      before do
        child = build_scope
        child.mark_inclusion
        scope.absorb(child)
      end

      it { is_expected.to be_empty }
    end

    context "when an ancestor's helper body references the name" do
      let(:ancestors) do
        ancestor = build_scope
        ancestor.add_helper_reference(:value)
        [ancestor]
      end

      it { is_expected.to be_empty }
    end
  end
end
