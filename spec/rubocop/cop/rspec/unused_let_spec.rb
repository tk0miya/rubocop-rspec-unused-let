# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe RuboCop::Cop::RSpec::UnusedLet, :config do
  include_context "with default RSpec/Language config"

  let(:cop_config) { { "CheckLetBang" => true } }

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
        context "when `let(:value)` is overridden at the top level" do
          it "ignores it" do
            expect_no_offenses(<<~RUBY)
              RSpec.describe JsonFormatValidator, type: :validator do
                let(:value) { "String" }

                it { is_expected.to be_invalid }
              end
            RUBY
          end
        end

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
        let(:cop_config) { { "CheckLetBang" => true, "CheckHelperSpecs" => true } }

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

        context "when a reference is reachable through a nested inclusion" do
          it "keeps the let that satisfies it" do
            expect_no_offenses(<<~RUBY)
              RSpec.shared_examples "outer" do
                include_examples "inner"
              end

              RSpec.shared_examples "inner" do
                it { expect(name).to eq("value") }
              end

              RSpec.describe Foo do
                let(:name) { "value" }

                it_behaves_like "outer"
              end
            RUBY
          end
        end

        context "when the reference sits in a nested group inside the shared block" do
          it "keeps the includer's let it resolves" do
            expect_no_offenses(<<~RUBY)
              RSpec.shared_examples "a thing" do
                context "nested" do
                  it { expect(value).to eq(1) }
                end
              end

              RSpec.describe Foo do
                let(:value) { 1 }

                it_behaves_like "a thing"
              end
            RUBY
          end
        end

        context "when the shared block defines the referenced name itself" do
          it "flags the includer's like-named let" do
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

        context "when the shared example is named with a symbol" do
          it "resolves it" do
            expect_no_offenses(<<~RUBY)
              RSpec.shared_examples :a_thing do
                it { expect(name).to eq("value") }
              end

              RSpec.describe Foo do
                let(:name) { "value" }

                it_behaves_like :a_thing
              end
            RUBY
          end
        end

        context "when the same name is defined in an enclosing group" do
          it "resolves the inclusion to the nearest (shadowing) definition" do
            expect_offense(<<~RUBY)
              RSpec.shared_examples "common" do
                it { expect(outer).to eq(1) }
              end

              RSpec.describe Foo do
                context "inner" do
                  shared_examples "common" do
                    it { expect(inner).to eq(1) }
                  end

                  let(:inner) { 1 }
                  let(:outer) { 2 }
                  ^^^^^^^^^^^ `let(:outer)` is not referenced anywhere. Remove it or reference it in an example.

                  it_behaves_like "common"
                end
              end
            RUBY
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

        context "when the definition lives in a sibling group" do
          it "cannot see it and stays conservative" do
            # Bar's inclusion cannot see Foo's group-local shared block.
            expect_no_offenses(<<~RUBY)
              RSpec.describe Foo do
                shared_examples "common" do
                  it { expect(a).to eq(1) }
                end

                let(:a) { 1 }

                it_behaves_like "common"
              end

              RSpec.describe Bar do
                let(:b) { 2 }

                it_behaves_like "common"
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

    context "with lets defined inside a shared example block" do
      it "does not flag them, at any nesting depth" do
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
      let(:cop_config) do
        {
          "CheckLetBang" => true,
          "SharedExamplePaths" => [File.join(support_dir, "*.rb")]
        }
      end

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
      let(:cop_config) { { "CheckLetBang" => true, "SharedExamplePaths" => [] } }

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
      let(:cop_config) do
        {
          "CheckLetBang" => true,
          "SharedExamplePaths" => [File.join(support_dir, "missing", "*.rb")]
        }
      end

      it "tolerates the empty match and stays conservative" do
        expect_no_offenses(<<~RUBY)
          RSpec.describe Foo do
            let(:unused) { 1 }

            it_behaves_like "an external thing"
          end
        RUBY
      end
    end

    context "when the same file backs many investigations" do
      let(:cop_config) do
        {
          "CheckLetBang" => true,
          "SharedExamplePaths" => [File.join(support_dir, "*.rb")]
        }
      end

      around do |example|
        described_class.external_definitions_cache.clear
        example.run
        described_class.external_definitions_cache.clear
      end

      it "parses and indexes each external file once, reusing the cache" do
        path = File.expand_path(File.join(support_dir, "shared.rb"))
        allow(RuboCop::AST::ProcessedSource).to receive(:from_file).and_call_original

        3.times { cop.send(:definitions_for, path) }

        expect(RuboCop::AST::ProcessedSource).to have_received(:from_file).once
      end
    end

    context "when a pre-loaded file cannot be parsed" do
      before { File.write(File.join(support_dir, "broken.rb"), "def oops(") }

      let(:cop_config) do
        {
          "CheckLetBang" => true,
          "SharedExamplePaths" => [File.join(support_dir, "broken.rb")]
        }
      end

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
