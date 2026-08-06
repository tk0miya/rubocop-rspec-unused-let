# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe RuboCop::Cop::RSpec::UnusedLet, :config do
  include_context "with default RSpec/Language config"

  let(:cop_config) do
    { "CheckLetBang" => true, "CheckSubject" => true, "CheckSharedExamples" => true }
  end

  context "with let" do
    context "when unused" do
      context "with a `let` block" do
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
      end

      context "with a block-pass definition" do
        it "flags it and removes the definition" do
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
      end

      context "with a do..end block" do
        it "flags it and removes the definition" do
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
      context "when the reference is in an example" do
        it "does not flag it" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              let(:value) { 1 }

              it { expect(value).to eq(1) }
            end
          RUBY
        end
      end

      context "when the reference is in a nested example group" do
        it "does not flag it" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              let(:value) { 1 }

              context "when nested" do
                it { expect(value).to eq(1) }
              end
            end
          RUBY
        end
      end

      context "when the reference is in an ancestor let block that runs in the example's scope" do
        it "does not flag it" do
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
      end

      context "when the reference is in an ancestor subject block" do
        it "does not flag it" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              subject { described_class.new(inner) }

              context "when nested" do
                let(:inner) { 1 }

                it { is_expected.to be_valid }
              end
            end
          RUBY
        end
      end

      context "when the reference goes through send" do
        it "does not flag it" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              let(:value) { 1 }

              it { expect(send(:value)).to eq(1) }
            end
          RUBY
        end
      end

      context "when the reference uses hash value omission", :ruby31 do
        it "does not flag it" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              let(:value) { 1 }

              before { setup(value:) }

              it { expect(true).to be(true) }
            end
          RUBY
        end
      end

      context "when part of an override chain" do
        context "when redefined in a nested group (super chain)" do
          it "keeps every member of the chain" do
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
        end

        context "when no member of the chain is referenced" do
          it "flags the whole chain" do
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
        end

        context "when an inner override is never referenced by its own group" do
          it "flags the inner override" do
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
        end

        context "when only the inner override is referenced" do
          it "keeps the outer definition" do
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
        end

        context "when a same-group redefinition chain is unreferenced" do
          it "flags every definition in the chain" do
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
      end

      context "when the same name is defined in sibling groups" do
        context "when one sibling references it and the other does not" do
          it "flags only the unreferenced sibling" do
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
        end

        context "when a sibling makes a plain reference to the name" do
          it "does not let it reach the other sibling's let" do
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
        end

        context "when a sibling references the name from a helper" do
          it "does not let it reach the other sibling's let" do
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
      end

      context "when `type: :validator` (rspec-validator_spec_helper) is in scope" do
        context "when `let(:value)` is overridden in a nested context" do
          it "ignores it" do
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
        end

        context "when a let's name is not one the helper injects" do
          it "still flags it" do
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
    end

    context "with a helper spec" do
      context "when CheckHelperSpecs is disabled (default)" do
        context "with `type: :helper` metadata" do
          it "ignores its lets, which the auto-included module may reference" do
            expect_no_offenses(<<~RUBY)
              RSpec.describe MyHelper, type: :helper do
                let(:current_user) { User.new }

                it { expect(helper.greeting).to eq("Hi") }
              end
            RUBY
          end
        end

        context "with `type: :helper` and a `let` in a nested context" do
          it "ignores the nested and ancestor lets" do
            expect_no_offenses(<<~RUBY)
              RSpec.describe MyHelper, type: :helper do
                let(:current_user) { User.new }

                context "when signed in" do
                  let(:token) { "abc" }

                  it { expect(helper.greeting).to eq("Hi") }
                end
              end
            RUBY
          end
        end

        context "with `type: :helper` on a nested group" do
          it "ignores ancestor lets too" do
            expect_no_offenses(<<~RUBY)
              RSpec.describe MyHelper do
                let(:current_user) { User.new }

                describe "#greeting", type: :helper do
                  it { expect(helper.greeting).to eq("Hi") }
                end
              end
            RUBY
          end
        end

        context "with a `spec/helpers` file location and no `type:`" do
          it "ignores its lets" do
            expect_no_offenses(<<~RUBY, "spec/helpers/my_helper_spec.rb")
              RSpec.describe MyHelper do
                let(:current_user) { User.new }

                it { expect(helper.greeting).to eq("Hi") }
              end
            RUBY
          end
        end

        context "with a `spec/helpers` file but an explicit non-helper `type:`" do
          it "still checks the group" do
            expect_offense(<<~RUBY, "spec/helpers/my_helper_spec.rb")
              RSpec.describe MyHelper, type: :model do
                let(:unused) { 1 }
                ^^^^^^^^^^^^ `let(:unused)` is not referenced anywhere. Remove it or reference it in an example.

                it { expect(true).to be(true) }
              end
            RUBY
          end
        end
      end

      context "when CheckHelperSpecs is enabled" do
        let(:cop_config) { super().merge("CheckHelperSpecs" => true) }

        context "with `type: :helper` metadata" do
          it "flags an unused let" do
            expect_offense(<<~RUBY)
              RSpec.describe MyHelper, type: :helper do
                let(:unused) { 1 }
                ^^^^^^^^^^^^ `let(:unused)` is not referenced anywhere. Remove it or reference it in an example.

                it { expect(helper.greeting).to eq("Hi") }
              end
            RUBY
          end
        end

        context "with a `spec/helpers` file location" do
          it "flags an unused let" do
            expect_offense(<<~RUBY, "spec/helpers/my_helper_spec.rb")
              RSpec.describe MyHelper do
                let(:unused) { 1 }
                ^^^^^^^^^^^^ `let(:unused)` is not referenced anywhere. Remove it or reference it in an example.

                it { expect(true).to be(true) }
              end
            RUBY
          end
        end
      end
    end

    context "when the spec has a shared example inclusion" do
      context "when the inclusion resolves within the file" do
        context "when the shared block references some of the includer's lets" do
          it "keeps those and flags the rest" do
            expect_offense(<<~RUBY)
              RSpec.shared_examples "a thing" do
                it { expect(name).to eq("value") }
              end

              RSpec.describe Foo do
                let(:name) { "value" }
                let(:unused) { 1 }
                ^^^^^^^^^^^^ `let(:unused)` is not referenced anywhere. Remove it or reference it in an example.

                it_behaves_like "a thing"
              end
            RUBY
          end
        end

        context "when the block defines the name itself as a helper method" do
          it "flags a same-named `let` the isolated `it_behaves_like` never uses" do
            expect_offense(<<~RUBY)
              RSpec.shared_examples "a thing" do
                def name
                  "own"
                end

                it { expect(name).to eq("own") }
              end

              RSpec.describe Foo do
                let(:name) { "value" }
                ^^^^^^^^^^ `let(:name)` is not referenced anywhere. Remove it or reference it in an example.

                it_behaves_like "a thing"
              end
            RUBY
          end
        end

        context "when the shared example is defined after the inclusion" do
          it "still resolves it" do
            expect_no_offenses(<<~RUBY)
              RSpec.describe Foo do
                let(:name) { "value" }

                it_behaves_like "a thing"
              end

              RSpec.shared_examples "a thing" do
                it { expect(name).to eq("value") }
              end
            RUBY
          end
        end

        context "when the shared block and the includer define the same name" do
          context "when included with `it_behaves_like` (a nested group)" do
            it "flags the includer's like-named let, isolated by the nested group" do
              expect_offense(<<~RUBY)
                RSpec.shared_examples "a thing" do
                  let(:helper) { 1 }

                  it { expect(helper).to eq(1) }
                end

                RSpec.describe Foo do
                  let(:helper) { 2 }
                  ^^^^^^^^^^^^ `let(:helper)` is not referenced anywhere. Remove it or reference it in an example.

                  it_behaves_like "a thing"
                end
              RUBY
            end
          end

          context "when included inline with `include_examples`" do
            it "keeps the includer's like-named let, which the inline block references" do
              expect_no_offenses(<<~RUBY)
                RSpec.shared_examples "a thing" do
                  let(:helper) { 1 }

                  it { expect(helper).to eq(1) }
                end

                RSpec.describe Foo do
                  include_examples "a thing"
                  let(:helper) { 2 }
                end
              RUBY
            end
          end

          context "when the inline block never references the name" do
            it "flags the includer's like-named let" do
              expect_offense(<<~RUBY)
                RSpec.shared_context "a thing" do
                  let(:helper) { 1 }
                end

                RSpec.describe Foo do
                  include_context "a thing"
                  let(:helper) { 2 }
                  ^^^^^^^^^^^^ `let(:helper)` is not referenced anywhere. Remove it or reference it in an example.
                end
              RUBY
            end
          end

          context "when an inline inclusion sits below the like-named let in an ancestor" do
            it "flags the ancestor's let, which the inline block does not reach" do
              expect_offense(<<~RUBY)
                RSpec.shared_examples "a thing" do
                  let(:helper) { 1 }

                  it { expect(helper).to eq(1) }
                end

                RSpec.describe Foo do
                  let(:helper) { 2 }
                  ^^^^^^^^^^^^ `let(:helper)` is not referenced anywhere. Remove it or reference it in an example.

                  context "inner" do
                    include_examples "a thing"
                  end
                end
              RUBY
            end
          end
        end
      end

      context "when the inclusion cannot be resolved" do
        context "when the shared example is not defined in the file" do
          it "ignores every let visible at the inclusion" do
            expect_no_offenses(<<~RUBY)
              RSpec.describe Foo do
                let(:name) { "value" }

                it_behaves_like "a thing"
              end
            RUBY
          end
        end

        context "when the shared example is included under a dynamic name" do
          it "stays conservative and ignores visible lets" do
            expect_no_offenses(<<~RUBY)
              RSpec.shared_examples "a thing" do
                it { expect(true).to be(true) }
              end

              RSpec.describe Foo do
                let(:name) { "value" }

                it_behaves_like SHARED
              end
            RUBY
          end
        end

        context "when the group also includes an unresolvable shared example" do
          it "stays conservative for the whole group, keeping every visible let" do
            # `never_used` would be flagged if `known` were the only inclusion,
            # but the unresolvable `external` forces the whole group conservative.
            expect_no_offenses(<<~RUBY)
              RSpec.shared_examples "known" do
                it { expect(used).to eq(1) }
              end

              RSpec.describe Foo do
                let(:used) { 1 }
                let(:never_used) { 2 }

                it_behaves_like "known"
                it_behaves_like "external"
              end
            RUBY
          end
        end

        context "when only one subtree carries the inclusion" do
          it "still checks the sibling subtrees" do
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
    end

    context "when defined inside a shared example block" do
      context "when CheckSharedExamples is enabled (default)" do
        context "when the block carries examples" do
          context "when nothing in the block references the let" do
            it "flags it and removes the definition" do
              expect_offense(<<~RUBY)
                RSpec.shared_examples "a thing" do
                  let(:used) { 1 }
                  let(:unused) { 2 }
                  ^^^^^^^^^^^^ `let(:unused)` is not referenced anywhere in this shared example group. Remove it or reference it in an example.

                  it { expect(used).to eq(1) }
                end
              RUBY

              expect_correction(<<~RUBY)
                RSpec.shared_examples "a thing" do
                  let(:used) { 1 }

                  it { expect(used).to eq(1) }
                end
              RUBY
            end
          end

          context "when a nested group's example references the let" do
            it "keeps it" do
              expect_no_offenses(<<~RUBY)
                RSpec.shared_examples "a thing" do
                  let(:used) { 1 }

                  context "nested" do
                    it { expect(used).to eq(1) }
                  end
                end
              RUBY
            end
          end

          context "when the unused let sits in a nested group" do
            it "flags it" do
              expect_offense(<<~RUBY)
                RSpec.shared_examples "a thing" do
                  it { expect(true).to be(true) }

                  context "nested" do
                    let(:unused) { 1 }
                    ^^^^^^^^^^^^ `let(:unused)` is not referenced anywhere in this shared example group. Remove it or reference it in an example.
                  end
                end
              RUBY
            end
          end

          context "when a let of the block is built from a name it does not define" do
            it "keeps the let and leaves the free reference alone" do
              expect_no_offenses(<<~RUBY)
                RSpec.shared_examples "a thing" do
                  let(:local) { from_the_includer }

                  it { expect(local).to eq(1) }
                end
              RUBY
            end
          end

          context "when the block holds an unresolvable inclusion" do
            it "stays conservative and keeps every let" do
              expect_no_offenses(<<~RUBY)
                RSpec.shared_examples "a thing" do
                  let(:maybe_used) { 1 }

                  it { expect(true).to be(true) }

                  it_behaves_like "something external"
                end
              RUBY
            end
          end

          context "when the block sits inside an example group" do
            it "checks it without disturbing the outer group" do
              expect_offense(<<~RUBY)
                RSpec.describe Foo do
                  shared_examples "a thing" do
                    let(:unused) { 1 }
                    ^^^^^^^^^^^^ `let(:unused)` is not referenced anywhere in this shared example group. Remove it or reference it in an example.

                    it { expect(outer).to eq(1) }
                  end

                  let(:outer) { 1 }

                  it_behaves_like "a thing"
                end
              RUBY
            end
          end

          context "when the includer of an inline inclusion references the let" do
            it "flags it anyway, inclusion sites never being followed back" do
              expect_offense(<<~RUBY)
                RSpec.describe Foo do
                  shared_examples "a thing" do
                    let(:x) { 1 }
                    ^^^^^^^ `let(:x)` is not referenced anywhere in this shared example group. Remove it or reference it in an example.

                    it { expect(true).to be(true) }
                  end

                  include_examples "a thing"

                  it { expect(x).to eq(1) }
                end
              RUBY
            end
          end

          context "when it holds a nested shared block that carries examples too" do
            it "flags the inner block's unused let as well" do
              expect_offense(<<~RUBY)
                RSpec.shared_examples "a thing" do
                  it { expect(1).to eq(1) }

                  shared_examples "inner" do
                    let(:unused) { 2 }
                    ^^^^^^^^^^^^ `let(:unused)` is not referenced anywhere in this shared example group. Remove it or reference it in an example.

                    it { expect(1).to eq(1) }
                  end
                end
              RUBY
            end
          end
        end

        context "when the block carries no examples" do
          context "when it holds nothing but lets" do
            it "leaves the provider's lets alone" do
              expect_no_offenses(<<~RUBY)
                RSpec.shared_context "with a thing" do
                  let(:provided) { 1 }
                end
              RUBY
            end
          end

          context "when it holds a nested group" do
            it "leaves the nested lets alone as well" do
              expect_no_offenses(<<~RUBY)
                RSpec.shared_context "with a thing" do
                  let(:provided) { 1 }

                  context "nested" do
                    let(:also_provided) { 2 }
                  end
                end
              RUBY
            end
          end

          context "when it holds a nested shared block that carries examples" do
            it "leaves the lets of both alone, the examples being the inner block's" do
              expect_no_offenses(<<~RUBY)
                RSpec.shared_context "with a thing" do
                  let(:provided) { 1 }

                  shared_examples "inner" do
                    let(:unused) { 2 }

                    it { expect(1).to eq(1) }
                  end
                end
              RUBY
            end
          end

          context "when it is nested inside a shared block that carries examples" do
            it "leaves the provider's lets alone, judging it on its own contents" do
              expect_no_offenses(<<~RUBY)
                RSpec.shared_examples "a thing" do
                  it { expect(1).to eq(1) }

                  shared_context "with a thing" do
                    let(:provided) { 2 }
                  end
                end
              RUBY
            end
          end
        end
      end

      context "when CheckSharedExamples is disabled" do
        let(:cop_config) { super().merge("CheckSharedExamples" => false) }

        context "when the block carries examples" do
          it "does not flag its lets" do
            expect_no_offenses(<<~RUBY)
              RSpec.shared_examples "a thing" do
                let(:unused) { 1 }

                it { expect(value).to eq(1) }
              end
            RUBY
          end
        end

        context "when the block carries no examples" do
          it "does not flag them either, at any nesting depth" do
            expect_no_offenses(<<~RUBY)
              RSpec.shared_examples "a thing" do
                let(:direct) { 1 }

                context "nested" do
                  let(:nested) { 2 }
                end
              end
            RUBY
          end
        end
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
        let(:cop_config) { super().merge("CheckLetBang" => false) }

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

  context "with subject" do
    context "when unused" do
      context "when CheckSubject is enabled (default)" do
        context "with an anonymous subject" do
          it "flags it and removes the definition" do
            expect_offense(<<~RUBY)
              RSpec.describe Foo do
                subject { described_class.new }
                ^^^^^^^ `subject` is not referenced anywhere. Remove it or reference it in an example.

                it { expect(Foo.count).to eq(0) }
              end
            RUBY

            expect_correction(<<~RUBY)
              RSpec.describe Foo do

                it { expect(Foo.count).to eq(0) }
              end
            RUBY
          end
        end

        context "with a named subject" do
          it "flags it and removes the definition" do
            expect_offense(<<~RUBY)
              RSpec.describe Foo do
                subject(:widget) { described_class.new }
                ^^^^^^^^^^^^^^^^ `subject(:widget)` is not referenced anywhere. Remove it or reference it in an example.

                it { expect(Foo.count).to eq(0) }
              end
            RUBY

            expect_correction(<<~RUBY)
              RSpec.describe Foo do

                it { expect(Foo.count).to eq(0) }
              end
            RUBY
          end
        end

        context "when only a same-named `let` is referenced elsewhere" do
          it "flags the subject in the group that never uses it" do
            expect_offense(<<~RUBY)
              RSpec.describe Foo do
                context "one" do
                  subject(:widget) { described_class.new }
                  ^^^^^^^^^^^^^^^^ `subject(:widget)` is not referenced anywhere. Remove it or reference it in an example.

                  it { expect(Foo.count).to eq(0) }
                end

                context "two" do
                  let(:widget) { described_class.new }

                  it { expect(widget).to be_a(Foo) }
                end
              end
            RUBY
          end
        end
      end

      context "when CheckSubject is disabled" do
        let(:cop_config) { super().merge("CheckSubject" => false) }

        it "does not flag it, but still flags a `let`" do
          expect_offense(<<~RUBY)
            RSpec.describe Foo do
              subject(:widget) { described_class.new }
              let(:unused) { 1 }
              ^^^^^^^^^^^^ `let(:unused)` is not referenced anywhere. Remove it or reference it in an example.

              it { expect(Foo.count).to eq(0) }
            end
          RUBY
        end
      end
    end

    context "when referenced" do
      context "with the one-liner `is_expected`" do
        it "does not flag it" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              subject { described_class.new }

              it { is_expected.to be_valid }
            end
          RUBY
        end
      end
    end

    context "when a nested group declares its own subject" do
      context "with a block" do
        it "does not flag the outer one, both answering to the same name" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              subject { described_class.new }

              context "nested" do
                subject { described_class.new(1) }

                it { is_expected.to be_valid }
              end
            end
          RUBY
        end
      end

      context "with a block argument" do
        it "flags the outer one, the declaration being no reference to it" do
          expect_offense(<<~RUBY)
            RSpec.describe Foo do
              subject { described_class.new }
              ^^^^^^^ `subject` is not referenced anywhere. Remove it or reference it in an example.

              context "nested" do
                subject(:widget, &:itself)

                it { expect(Foo.count).to eq(0) }
              end
            end
          RUBY
        end
      end

      context "with a numbered block" do
        it "flags the outer one, the declaration being no reference to it" do
          expect_offense(<<~RUBY)
            RSpec.describe Foo do
              subject { described_class.new }
              ^^^^^^^ `subject` is not referenced anywhere. Remove it or reference it in an example.

              context "nested" do
                subject { _1 }

                it { expect(Foo.count).to eq(0) }
              end
            end
          RUBY
        end
      end
    end

    context "when the spec has a shared example inclusion" do
      context "when the shared block uses the one-liner syntax" do
        it "does not flag the subject it consumes" do
          expect_no_offenses(<<~RUBY)
            RSpec.shared_examples "a valid thing" do
              it { is_expected.to be_valid }
            end

            RSpec.describe Foo do
              subject { described_class.new }

              it_behaves_like "a valid thing"
            end
          RUBY
        end
      end

      context "when the shared block references no subject" do
        it "flags the subject" do
          expect_offense(<<~RUBY)
            RSpec.shared_examples "a counted thing" do
              it { expect(Foo.count).to eq(0) }
            end

            RSpec.describe Foo do
              subject { described_class.new }
              ^^^^^^^ `subject` is not referenced anywhere. Remove it or reference it in an example.

              it_behaves_like "a counted thing"
            end
          RUBY
        end
      end

      context "when the shared block declares its own subject" do
        it "flags the subject of a nested inclusion's including group" do
          expect_offense(<<~RUBY)
            RSpec.shared_examples "a valid thing" do
              subject { described_class.new }

              it { is_expected.to be_valid }
            end

            RSpec.describe Foo do
              subject { described_class.new(1) }
              ^^^^^^^ `subject` is not referenced anywhere. Remove it or reference it in an example.

              it_behaves_like "a valid thing"
            end
          RUBY
        end
      end

      context "when an inline inclusion's block declares a subject it never uses" do
        it "flags the overriding subject" do
          expect_offense(<<~RUBY)
            RSpec.shared_context "with a thing" do
              subject { described_class.new }
            end

            RSpec.describe Foo do
              include_context "with a thing"

              subject { described_class.new(1) }
              ^^^^^^^ `subject` is not referenced anywhere. Remove it or reference it in an example.
            end
          RUBY
        end
      end

      context "when the inclusion cannot be resolved" do
        it "does not flag the subject visible at it" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              subject { described_class.new }

              it_behaves_like "an external thing"
            end
          RUBY
        end
      end
    end

    context "when defined inside a shared example block" do
      context "when CheckSharedExamples is enabled (default)" do
        context "when the block carries examples" do
          it "flags it" do
            expect_offense(<<~RUBY)
              RSpec.shared_examples "a thing" do
                subject { described_class.new }
                ^^^^^^^ `subject` is not referenced anywhere in this shared example group. Remove it or reference it in an example.

                it { expect(Foo.count).to eq(0) }
              end
            RUBY
          end
        end

        context "when the block carries no examples" do
          it "leaves the provider's subject alone" do
            expect_no_offenses(<<~RUBY)
              RSpec.shared_context "with a thing" do
                subject { described_class.new }
              end
            RUBY
          end
        end
      end

      context "when CheckSharedExamples is disabled" do
        let(:cop_config) { super().merge("CheckSharedExamples" => false) }

        it "does not flag it" do
          expect_no_offenses(<<~RUBY)
            RSpec.shared_examples "a thing" do
              subject { described_class.new }

              it { expect(Foo.count).to eq(0) }
            end
          RUBY
        end
      end
    end
  end

  context "with subject!" do
    context "when unused" do
      context "when CheckLetBang is enabled (default)" do
        context "when CheckSubject is enabled (default)" do
          it "flags it and removes the definition" do
            expect_offense(<<~RUBY)
              RSpec.describe Foo do
                subject! { create(:widget) }
                ^^^^^^^^ `subject!` is not referenced anywhere. Remove it or reference it in an example.

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

        context "when CheckSubject is disabled" do
          let(:cop_config) { super().merge("CheckSubject" => false) }

          it "does not flag it" do
            expect_no_offenses(<<~RUBY)
              RSpec.describe Foo do
                subject! { create(:widget) }

                it { expect(Widget.count).to eq(1) }
              end
            RUBY
          end
        end
      end

      context "when CheckLetBang is disabled" do
        let(:cop_config) { super().merge("CheckLetBang" => false) }

        it "does not flag it" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              subject! { create(:widget) }

              it { expect(Widget.count).to eq(1) }
            end
          RUBY
        end
      end
    end
  end

  context "with helper methods" do
    context "when unused" do
      context "with a multi-line def" do
        it "flags it and removes the definition" do
          expect_offense(<<~RUBY)
            RSpec.describe Foo do
              def unused
              ^^^^^^^^^^ `def unused` is not referenced anywhere. Remove it or reference it in an example.
                1
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
      end

      context "with a one-line def" do
        it "flags it and removes the definition", :ruby30 do
          expect_offense(<<~RUBY)
            RSpec.describe Foo do
              def unused = 1
              ^^^^^^^^^^ `def unused` is not referenced anywhere. Remove it or reference it in an example.

              it { expect(true).to be(true) }
            end
          RUBY

          expect_correction(<<~RUBY)
            RSpec.describe Foo do

              it { expect(true).to be(true) }
            end
          RUBY
        end
      end
    end

    context "when referenced" do
      context "when the reference is in an example" do
        it "does not flag it" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              def value
                1
              end

              it { expect(value).to eq(1) }
            end
          RUBY
        end
      end
    end

    context "when defined inside a nested definee scope" do
      context "with a stub class" do
        it "does not treat its method as a group helper" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              class Dummy
                def call
                  1
                end
              end

              it { expect(Dummy.new.call).to eq(1) }
            end
          RUBY
        end
      end

      context "with rspec-rails' anonymous controller" do
        it "does not treat its method as a group helper" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              controller do
                def index
                  head :no_content
                end
              end

              it { expect(response).to be_successful }
            end
          RUBY
        end
      end

      context "with a block of a DSL the cop knows nothing about" do
        it "does not treat its method as a group helper" do
          expect_no_offenses(<<~RUBY)
            RSpec.describe Foo do
              with_model :Blog do
                model do
                  def title_upcased
                    title.upcase
                  end
                end
              end

              it { expect(Blog.new(title: "a").title_upcased).to eq("A") }
            end
          RUBY
        end
      end
    end

    context "when defined inside a shared example block" do
      context "when CheckSharedExamples is enabled (default)" do
        it "flags it" do
          expect_offense(<<~RUBY)
            RSpec.shared_examples "a thing" do
              def unused
              ^^^^^^^^^^ `def unused` is not referenced anywhere in this shared example group. Remove it or reference it in an example.
                1
              end

              it { expect(true).to be(true) }
            end
          RUBY
        end
      end

      context "when CheckSharedExamples is disabled" do
        let(:cop_config) { super().merge("CheckSharedExamples" => false) }

        it "does not flag it" do
          expect_no_offenses(<<~RUBY)
            RSpec.shared_examples "a thing" do
              def helper
                1
              end

              it { expect(true).to be(true) }
            end
          RUBY
        end
      end
    end

    context "with a helper spec" do
      it "ignores it, which the auto-included module may reference" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe MyHelper, type: :helper do
            def current_user
              User.new
            end

            it { expect(helper.greeting).to eq("Hi") }
          end
        RUBY
      end
    end
  end

  context "with shared examples defined in external files" do
    let(:support_dir) { Dir.mktmpdir }

    before do
      File.write(File.join(support_dir, "shared.rb"), <<~RUBY)
        RSpec.shared_examples "an external thing" do
          it { expect(used).to eq(1) }
        end
      RUBY
    end

    after { FileUtils.remove_entry(support_dir) }

    context "when SharedExamplePaths points at the file" do
      let(:cop_config) { super().merge("SharedExamplePaths" => [File.join(support_dir, "*.rb")]) }

      it "keeps the lets the external block references and flags the rest" do
        expect_offense(<<~RUBY)
          RSpec.describe Foo do
            let(:used) { 1 }
            let(:unused) { 2 }
            ^^^^^^^^^^^^ `let(:unused)` is not referenced anywhere. Remove it or reference it in an example.

            it_behaves_like "an external thing"
          end
        RUBY
      end
    end

    context "when SharedExamplePaths is left empty" do
      let(:cop_config) { super().merge("SharedExamplePaths" => []) }

      it "stays conservative and silences every visible let" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:used) { 1 }
            let(:unused) { 2 }

            it_behaves_like "an external thing"
          end
        RUBY
      end
    end

    context "when SharedExamplePaths matches no files" do
      let(:cop_config) { super().merge("SharedExamplePaths" => [File.join(support_dir, "missing", "*.rb")]) }

      it "tolerates the empty match and stays conservative" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:unused) { 1 }

            it_behaves_like "an external thing"
          end
        RUBY
      end
    end

    # The shipped default is such a pattern, so this is how it finds a project's
    # own `spec/support`.
    context "when a pattern is relative" do
      let(:cop_config) { { "CheckLetBang" => true, "SharedExamplePaths" => ["*.rb"] } }

      before { allow(config).to receive(:base_dir_for_path_parameters).and_return(support_dir) }

      it "resolves it against the configuration's base directory" do
        expect_offense(<<~RUBY)
          RSpec.describe Foo do
            let(:used) { 1 }
            let(:unused) { 2 }
            ^^^^^^^^^^^^ `let(:unused)` is not referenced anywhere. Remove it or reference it in an example.

            it_behaves_like "an external thing"
          end
        RUBY
      end
    end

    # The caching and checksum mechanics that back this are unit-tested
    # directly in external_definitions_spec.rb; here it's enough to confirm
    # the cop stays conservative when a pre-loaded file can't be parsed.
    context "when a pre-loaded file cannot be parsed" do
      before { File.write(File.join(support_dir, "broken.rb"), "def oops(") }

      let(:cop_config) { super().merge("SharedExamplePaths" => [File.join(support_dir, "broken.rb")]) }

      it "skips the unparseable file and stays conservative" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:unused) { 1 }

            it_behaves_like "an external thing"
          end
        RUBY
      end
    end
  end
end
