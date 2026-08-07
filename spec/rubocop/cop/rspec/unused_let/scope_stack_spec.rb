# frozen_string_literal: true

RSpec.describe RuboCop::Cop::RSpec::UnusedLet::ScopeStack do
  def build_scope(kind: :example, type: nil)
    RuboCop::Cop::RSpec::UnusedLet::Scope.new(node: nil, kind: kind, type: type)
  end

  let(:scope_stack) { described_class.new(check_helper_specs: check_helper_specs) }
  let(:check_helper_specs) { false }

  describe "#push" do
    # Aggregated so the assertions need not say which scope holds a definition.
    def unreferenced_defs
      [ancestor, child].flat_map(&:unreferenced_defs)
    end

    subject { scope_stack.push(child) }

    before { scope_stack.push(ancestor) }

    context "when the scope references a name defined in an ancestor" do
      let(:ancestor) { build_scope.tap { _1.add_definition(:let, :value, :def_node) } }
      let(:child) { build_scope.tap { _1.add_reference(:value) } }

      it "marks the ancestor's definition referenced" do
        expect { subject }.to change { unreferenced_defs }.to(be_empty)
      end
    end

    context "when the scope references a name only in an example" do
      let(:ancestor) { build_scope.tap { _1.add_definition(:let, :value, :def_node) } }
      let(:child) { build_scope.tap { _1.add_reference_in_example(:value) } }

      it "marks the ancestor's definition referenced" do
        expect { subject }.to change { unreferenced_defs }.to(be_empty)
      end
    end

    context "when an ancestor's helper body references a name this scope defines" do
      let(:ancestor) { build_scope.tap { _1.add_reference(:value) } }
      let(:child) { build_scope.tap { _1.add_definition(:let, :value, :def_node) } }

      it "marks the scope's own definition referenced" do
        expect { subject }.to change { unreferenced_defs }.to(be_empty)
      end
    end

    context "when an ancestor's example (not helper body) references a name this scope defines" do
      let(:ancestor) { build_scope.tap { _1.add_reference_in_example(:value) } }
      let(:child) { build_scope.tap { _1.add_definition(:let, :value, :def_node) } }

      it "leaves the scope's own definition unreferenced" do
        expect { subject }.not_to change { unreferenced_defs }
          .from(contain_exactly(have_attributes(name: :value)))
      end
    end

    context "when the scope pulls in an unresolved shared inclusion" do
      let(:ancestor) { build_scope.tap { _1.add_definition(:let, :value, :def_node) } }
      let(:child) do
        build_scope.tap do |scope|
          scope.add_definition(:let, :other, :def_node)
          scope.mark_inclusion
        end
      end

      it "marks every definition in scope referenced" do
        expect { subject }.to change { unreferenced_defs }.to(be_empty)
      end
    end

    context "when the scope is a helper spec and CheckHelperSpecs is false" do
      let(:check_helper_specs) { false }
      let(:ancestor) { build_scope.tap { _1.add_definition(:let, :value, :def_node) } }
      let(:child) { build_scope(type: :helper).tap { _1.add_definition(:let, :other, :def_node) } }

      it "marks every definition in scope referenced" do
        expect { subject }.to change { unreferenced_defs }.to(be_empty)
      end
    end

    context "when the scope is a helper spec and CheckHelperSpecs is true" do
      let(:check_helper_specs) { true }
      let(:ancestor) { build_scope.tap { _1.add_definition(:let, :value, :def_node) } }
      let(:child) { build_scope(type: :helper).tap { _1.add_definition(:let, :other, :def_node) } }

      it "leaves every definition unreferenced" do
        expect { subject }.not_to change { unreferenced_defs }
          .from(contain_exactly(have_attributes(name: :value), have_attributes(name: :other)))
      end
    end
  end

  describe "#pop" do
    subject { scope_stack.pop }

    context "when the stack is empty" do
      it { is_expected.to be_nil }
    end

    context "when a scope was pushed" do
      let(:scope) { build_scope }

      before { scope_stack.push(scope) }

      it { is_expected.to be(scope) }
    end
  end

  describe "#shared_groups_for" do
    subject { scope_stack.shared_groups_for(scope) }

    context "when neither the scope nor its ancestors are shared groups" do
      let(:ancestor) { build_scope }
      let(:scope) { build_scope }

      before do
        scope_stack.push(ancestor)
        scope_stack.push(scope)
        scope_stack.pop
      end

      it { is_expected.to be_empty }
    end

    context "when an ancestor still on the stack is a shared group" do
      let(:ancestor) { build_scope(kind: :shared) }
      let(:scope) { build_scope }

      before do
        scope_stack.push(ancestor)
        scope_stack.push(scope)
        scope_stack.pop
      end

      it { is_expected.to contain_exactly(ancestor) }
    end

    context "when the popped scope itself is a shared group" do
      let(:scope) { build_scope(kind: :shared) }

      before do
        scope_stack.push(scope)
        scope_stack.pop
      end

      it { is_expected.to contain_exactly(scope) }
    end
  end
end
