# frozen_string_literal: true

RSpec.describe RuboCop::Cop::RSpec::UnusedLet::Scope do
  def build_scope(kind: :example)
    described_class.new(node: nil, kind: kind)
  end

  let(:def_node) { :a_let_node }

  describe "#unreferenced_defs" do
    subject { scope.unreferenced_defs }

    let(:scope) { build_scope }

    context "with a definition of one name" do
      before { scope.add_definition(:let, :value, def_node) }

      context "when it is never marked referenced" do
        it { is_expected.to contain_exactly(have_attributes(helper: :let, name: :value, node: def_node)) }
      end

      context "when the name has been marked referenced" do
        before { scope.mark_referenced(:value) }

        it { is_expected.to be_empty }
      end

      context "when only a different name has been marked referenced" do
        before { scope.mark_referenced(:other) }

        it { is_expected.to contain_exactly(have_attributes(helper: :let, name: :value, node: def_node)) }
      end
    end

    context "with an aliased definition" do
      before { scope.add_definition(:subject, :widget, def_node, alias_name: :subject) }

      context "when only the alias has been marked referenced" do
        before { scope.mark_referenced(:subject) }

        it { is_expected.to be_empty }
      end

      context "when only the declared name has been marked referenced" do
        before { scope.mark_referenced(:widget) }

        it { is_expected.to be_empty }
      end

      context "when neither name has been marked referenced" do
        it { is_expected.to contain_exactly(have_attributes(helper: :subject, name: :widget)) }
      end
    end
  end

  describe "#defined_names" do
    subject { scope.defined_names }

    let(:scope) { build_scope }

    before do
      scope.add_definition(:let, :first, :first_node)
      scope.add_definition(:let!, :second, :second_node)
      scope.add_definition(:subject, :third, :third_node, alias_name: :subject)
    end

    it { is_expected.to eq(%i[first second third subject]) }
  end

  describe "#shared?" do
    subject { scope.shared? }

    context "when the scope is an example group" do
      let(:scope) { build_scope }

      it { is_expected.to be(false) }
    end

    context "when the scope is a shared group" do
      let(:scope) { build_scope(kind: :shared) }

      it { is_expected.to be(true) }
    end
  end
end
