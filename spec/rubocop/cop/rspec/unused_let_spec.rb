# frozen_string_literal: true

RSpec.describe RuboCop::Cop::RSpec::UnusedLet, :config do
  include_context "with default RSpec/Language config"

  let(:cop_config) { { "CheckLetBang" => true } }

  context "with let" do
    context "when unused" do
      it "flags it and removes the definition" do
        expect_offense(<<~RUBY)
          RSpec.describe Foo do
            let(:used) { 1 }
            let(:unused) { 2 }
            ^^^^^^^^^^^^ `let(:unused)` is not referenced anywhere. Remove it or reference it in an example.

            it { expect(used).to eq(1) }
          end
        RUBY

        expect_correction(<<~RUBY)
          RSpec.describe Foo do
            let(:used) { 1 }

            it { expect(used).to eq(1) }
          end
        RUBY
      end

      it "flags multiple unused lets independently" do
        expect_offense(<<~RUBY)
          RSpec.describe Foo do
            let(:first) { 1 }
            ^^^^^^^^^^^ `let(:first)` is not referenced anywhere. Remove it or reference it in an example.
            let(:second) { 2 }
            ^^^^^^^^^^^^ `let(:second)` is not referenced anywhere. Remove it or reference it in an example.

            it { expect(true).to be(true) }
          end
        RUBY

        expect_correction(<<~RUBY)
          RSpec.describe Foo do

            it { expect(true).to be(true) }
          end
        RUBY
      end

      it "flags an unused string-named let" do
        expect_offense(<<~RUBY)
          RSpec.describe Foo do
            let("unused") { 1 }
            ^^^^^^^^^^^^^ `let(:unused)` is not referenced anywhere. Remove it or reference it in an example.

            it { expect(true).to be(true) }
          end
        RUBY

        expect_correction(<<~RUBY)
          RSpec.describe Foo do

            it { expect(true).to be(true) }
          end
        RUBY
      end

      it "flags an unused let defined with a block-pass" do
        expect_offense(<<~RUBY)
          RSpec.describe Foo do
            let(:unused, &:computed)
            ^^^^^^^^^^^^^^^^^^^^^^^^ `let(:unused)` is not referenced anywhere. Remove it or reference it in an example.

            it { expect(true).to be(true) }
          end
        RUBY

        expect_correction(<<~RUBY)
          RSpec.describe Foo do

            it { expect(true).to be(true) }
          end
        RUBY
      end

      it "flags an unused let defined with a do..end block" do
        expect_offense(<<~RUBY)
          RSpec.describe Foo do
            let(:unused) do
            ^^^^^^^^^^^^ `let(:unused)` is not referenced anywhere. Remove it or reference it in an example.
              value = 1
              value + 1
            end

            it { expect(true).to be(true) }
          end
        RUBY

        expect_correction(<<~RUBY)
          RSpec.describe Foo do

            it { expect(true).to be(true) }
          end
        RUBY
      end

      context "when a known gem's `type:` metadata does not apply" do
        it "flags `let(:value)` when no metadata is present" do
          expect_offense(<<~RUBY)
            RSpec.describe JsonFormatValidator do
              let(:value) { "String" }
              ^^^^^^^^^^^ `let(:value)` is not referenced anywhere. Remove it or reference it in an example.

              it { is_expected.to be_invalid }
            end
          RUBY
        end

        it "flags `let(:value)` when the metadata is a different type" do
          expect_offense(<<~RUBY)
            RSpec.describe JsonFormatValidator, type: :model do
              let(:value) { "String" }
              ^^^^^^^^^^^ `let(:value)` is not referenced anywhere. Remove it or reference it in an example.

              it { is_expected.to be_invalid }
            end
          RUBY
        end

        it "flags `let(:value)` when an inner context overrides the type" do
          expect_offense(<<~RUBY)
            RSpec.describe JsonFormatValidator, type: :validator do
              context "as a model", type: :model do
                let(:value) { "String" }
                ^^^^^^^^^^^ `let(:value)` is not referenced anywhere. Remove it or reference it in an example.

                it { is_expected.to be_invalid }
              end
            end
          RUBY
        end

        it "flags a let whose name is not covered even under `type: :validator`" do
          expect_offense(<<~RUBY)
            RSpec.describe JsonFormatValidator, type: :validator do
              let(:value) { "String" }
              let(:unused) { 1 }
              ^^^^^^^^^^^^ `let(:unused)` is not referenced anywhere. Remove it or reference it in an example.

              it { is_expected.to be_invalid }
            end
          RUBY
        end
      end
    end

    context "when referenced" do
      it "in an example" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:value) { 1 }

            it { expect(value).to eq(1) }
          end
        RUBY
      end

      it "in a hook" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:value) { 1 }

            before { value }

            it { expect(true).to be(true) }
          end
        RUBY
      end

      it "from another let" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:base) { 1 }
            let(:derived) { base + 1 }

            it { expect(derived).to eq(2) }
          end
        RUBY
      end

      it "in a nested example group" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:value) { 1 }

            context "when nested" do
              it { expect(value).to eq(1) }
            end
          end
        RUBY
      end

      it "inside a subject block" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:value) { 1 }

            subject { value + 1 }

            it { is_expected.to eq(2) }
          end
        RUBY
      end

      it "in an ancestor let block that runs in the example's scope" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:wrapper) { [inner] }

            context "when nested" do
              let(:inner) { 1 }

              it { expect(wrapper).to eq([1]) }
            end
          end
        RUBY
      end

      it "in an ancestor subject block" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            subject { inner + 1 }

            context "when nested" do
              let(:inner) { 1 }

              it { is_expected.to eq(2) }
            end
          end
        RUBY
      end

      it "in an ancestor hook block" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            before { inner }

            context "when nested" do
              let(:inner) { 1 }

              it { expect(true).to be(true) }
            end
          end
        RUBY
      end

      it "in a def helper defined in an ancestor group" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            def call_helper
              inner
            end

            context "when nested" do
              let(:inner) { 1 }

              it { call_helper }
            end
          end
        RUBY
      end

      it "in a def helper defined in the same group" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:value) { 1 }

            def call_helper
              value
            end

            it { expect(call_helper).to eq(1) }
          end
        RUBY
      end

      it "through send" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:value) { 1 }

            it { expect(send(:value)).to eq(1) }
          end
        RUBY
      end

      it "through public_send with a string" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:value) { 1 }

            it { expect(public_send("value")).to eq(1) }
          end
        RUBY
      end

      it "through hash value omission", :ruby31 do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:value) { 1 }

            before { setup(value:) }

            it { expect(true).to be(true) }
          end
        RUBY
      end

      it "with a string name" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let("value") { 1 }

            it { expect(value).to eq(1) }
          end
        RUBY
      end

      context "when part of an override chain" do
        it "is redefined in a nested group (super chain)" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              let(:value) { 1 }

              context "when nested" do
                let(:value) { super() + 1 }

                it { expect(value).to eq(2) }
              end
            end
          RUBY
        end

        it "overrides an outer definition" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              let(:value) { 1 }

              it { expect(value).to eq(1) }

              context "when overridden" do
                let(:value) { 2 }

                it { do_something }
              end
            end
          RUBY
        end
      end

      context "when `type: :validator` (rspec-validator_spec_helper) is in scope" do
        it "ignores `let(:value)` overridden at the top level" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe JsonFormatValidator, type: :validator do
              let(:value) { "String" }

              it { is_expected.to be_invalid }
            end
          RUBY
        end

        it "ignores `let(:value)` overridden in a nested context" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe JsonFormatValidator, type: :validator do
              describe "#validate_each" do
                context "when not JSON" do
                  let(:value) { "String" }

                  it { is_expected.to be_invalid }
                end
              end
            end
          RUBY
        end

        it "ignores the helper's other overridable lets" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe JsonFormatValidator, type: :validator do
              let(:attribute_names) { [:field] }
              let(:options) { { allow_nil: true } }
              let(:validator_name) { "CustomValidator" }
              let(:model_class) { Struct.new(:field) }

              it { is_expected.to be_invalid }
            end
          RUBY
        end

        it "ignores overrides when the metadata is set on an inner context" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe JsonFormatValidator do
              context "when JSON", type: :validator do
                let(:value) { "String" }

                it { is_expected.to be_invalid }
              end
            end
          RUBY
        end
      end
    end

    context "when a shared example inclusion is in scope" do
      it "ignores lets in the including group" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:name) { "value" }

            it_behaves_like "a thing"
          end
        RUBY
      end

      it "ignores lets visible from a nested inclusion" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:name) { "value" }

            context "when shared" do
              it_behaves_like "a thing"
            end
          end
        RUBY
      end

      it "ignores lets defined in the shared_examples block" do
        expect_no_offenses(<<~RUBY)
          RSpec.shared_examples "a thing" do
            let(:helper) { 1 }
          end
        RUBY
      end

      it "still flags lets in a sibling subtree without an inclusion" do
        expect_offense(<<~RUBY)
          RSpec.describe Foo do
            context "with shared" do
              it_behaves_like "a thing"
            end

            context "other" do
              let(:unused) { 1 }
              ^^^^^^^^^^^^ `let(:unused)` is not referenced anywhere. Remove it or reference it in an example.

              it { expect(true).to be(true) }
            end
          end
        RUBY
      end

      it "ignores lets when include_context is used" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:name) { "value" }

            include_context "shared setup"
          end
        RUBY
      end

      it "ignores lets when include_examples is used" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:name) { "value" }

            include_examples "a thing"
          end
        RUBY
      end
    end
  end

  context "with let!" do
    context "when unused" do
      context "when CheckLetBang is enabled (default)" do
        it "flags it and removes the definition" do
          expect_offense(<<~RUBY)
            RSpec.describe Foo do
              let!(:widget) { create(:widget) }
              ^^^^^^^^^^^^^ `let!(:widget)` is not referenced anywhere. Remove it or reference it in an example.

              it { expect(Widget.count).to eq(1) }
            end
          RUBY

          expect_correction(<<~RUBY)
            RSpec.describe Foo do

              it { expect(Widget.count).to eq(1) }
            end
          RUBY
        end
      end

      context "when CheckLetBang is disabled" do
        let(:cop_config) { { "CheckLetBang" => false } }

        it "does not flag it" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              let!(:widget) { create(:widget) }

              it { expect(Widget.count).to eq(1) }
            end
          RUBY
        end
      end
    end

    context "when referenced" do
      context "when CheckLetBang is enabled (default)" do
        it "does not flag it" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              let!(:widget) { create(:widget) }

              it { expect(widget).to be_present }
            end
          RUBY
        end
      end

      context "when CheckLetBang is disabled" do
        let(:cop_config) { { "CheckLetBang" => false } }

        it "does not flag it" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              let!(:widget) { create(:widget) }

              it { expect(widget).to be_present }
            end
          RUBY
        end
      end
    end
  end
end
