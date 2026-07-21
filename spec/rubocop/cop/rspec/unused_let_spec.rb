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
        it "flags `let(:value)` when the metadata is a different type" do
          expect_offense(<<~RUBY)
            RSpec.describe JsonFormatValidator, type: :model do
              let(:value) { "String" }
              ^^^^^^^^^^^ `let(:value)` is not referenced anywhere. Remove it or reference it in an example.

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

      it "through send" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:value) { 1 }

            it { expect(send(:value)).to eq(1) }
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

        it "flags the whole chain when no member is referenced" do
          expect_offense(<<~RUBY)
            RSpec.describe Foo do
              let(:value) { 1 }
              ^^^^^^^^^^^ `let(:value)` is not referenced anywhere. Remove it or reference it in an example.

              context "when nested" do
                let(:value) { super() + 1 }
                ^^^^^^^^^^^ `let(:value)` is not referenced anywhere. Remove it or reference it in an example.

                it { do_something }
              end
            end
          RUBY
        end

        it "flags an inner override that its own group never references" do
          expect_offense(<<~RUBY)
            RSpec.describe Foo do
              let(:value) { 1 }

              it { expect(value).to eq(1) }

              context "when overridden" do
                let(:value) { 2 }
                ^^^^^^^^^^^ `let(:value)` is not referenced anywhere. Remove it or reference it in an example.

                it { do_something }
              end
            end
          RUBY
        end

        it "keeps the outer definition when only the inner override is referenced" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              let(:value) { 1 }

              context "when overridden" do
                let(:value) { 2 }

                it { expect(value).to eq(2) }
              end
            end
          RUBY
        end

        it "flags an unreferenced same-group redefinition chain" do
          expect_offense(<<~RUBY)
            RSpec.describe Foo do
              let(:value) { 1 }
              ^^^^^^^^^^^ `let(:value)` is not referenced anywhere. Remove it or reference it in an example.
              let(:value) { 2 }
              ^^^^^^^^^^^ `let(:value)` is not referenced anywhere. Remove it or reference it in an example.

              it { do_something }
            end
          RUBY
        end
      end

      context "when the same name is defined in sibling groups" do
        it "flags the sibling that never references it, despite the other" do
          expect_offense(<<~RUBY)
            RSpec.describe Foo do
              context "referenced" do
                let(:value) { 1 }

                it { expect(value).to eq(1) }
              end

              context "unreferenced" do
                let(:value) { 2 }
                ^^^^^^^^^^^ `let(:value)` is not referenced anywhere. Remove it or reference it in an example.

                it { do_something }
              end
            end
          RUBY
        end

        it "does not let a sibling's plain reference reach the other's let" do
          expect_offense(<<~RUBY)
            RSpec.describe Foo do
              context "references a name it never defines" do
                it { expect(value).to eq(1) }
              end

              context "defines the name but never uses it" do
                let(:value) { 2 }
                ^^^^^^^^^^^ `let(:value)` is not referenced anywhere. Remove it or reference it in an example.

                it { do_something }
              end
            end
          RUBY
        end

        it "does not let a sibling's helper reference reach the other's let" do
          expect_offense(<<~RUBY)
            RSpec.describe Foo do
              context "references a name from a helper" do
                let(:proxy) { value }
                ^^^^^^^^^^^ `let(:proxy)` is not referenced anywhere. Remove it or reference it in an example.
              end

              context "defines the name but never uses it" do
                let(:value) { 2 }
                ^^^^^^^^^^^ `let(:value)` is not referenced anywhere. Remove it or reference it in an example.

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

        it "still flags a let whose name is not one the helper injects" do
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

    context "when a shared example inclusion is in scope" do
      it "ignores lets in the including group" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:name) { "value" }

            it_behaves_like "a thing"
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
  end
end
