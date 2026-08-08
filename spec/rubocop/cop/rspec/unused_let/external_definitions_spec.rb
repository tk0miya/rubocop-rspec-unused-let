# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe RuboCop::Cop::RSpec::UnusedLet::ExternalDefinitions do
  include_context "with UnusedLet AST helpers"

  let(:support_dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(support_dir) }

  def build(patterns: [File.join(support_dir, "*.rb")], base_dir: support_dir, cache: {})
    described_class.new(
      patterns: patterns,
      base_dir: base_dir,
      target_ruby_version: RUBY_VERSION.to_f,
      cache: cache
    )
  end

  describe "#paths" do
    subject { build(patterns: patterns).paths }

    before do
      File.write(File.join(support_dir, "b.rb"), "")
      File.write(File.join(support_dir, "a.rb"), "")
    end

    context "with a glob pattern" do
      let(:patterns) { [File.join(support_dir, "*.rb")] }

      it "expands it to absolute paths, in a stable sorted order" do
        expect(subject).to eq(
          [File.join(support_dir, "a.rb"), File.join(support_dir, "b.rb")].map { File.expand_path(_1) }
        )
      end
    end

    context "with no patterns" do
      let(:patterns) { [] }

      it { is_expected.to eq([]) }
    end

    context "when the pattern matches nothing" do
      let(:patterns) { [File.join(support_dir, "missing", "*.rb")] }

      it { is_expected.to eq([]) }
    end

    # The shipped default is such a pattern, so this is how it finds a
    # project's own `spec/support`.
    context "with a relative pattern" do
      let(:patterns) { ["*.rb"] }

      it "resolves it against base_dir" do
        expect(subject).not_to be_empty
      end
    end
  end

  describe "#checksum" do
    subject { build.checksum }

    let(:shared_file) { File.join(support_dir, "shared.rb") }
    let(:baseline) { build.checksum }

    before do
      File.write(shared_file, <<~RUBY)
        RSpec.shared_examples "a thing" do
          it { expect(used).to eq(1) }
        end
      RUBY

      baseline # force the lazy baseline before each context edits a file
    end

    context "when a pre-loaded file's content changes" do
      # Same byte count, so a size-based signature would miss this change.
      before { File.write(shared_file, File.read(shared_file).sub("used", "usee")) }

      it { is_expected.not_to eq(baseline) }
    end

    context "when only a pre-loaded file's mtime changes" do
      before do
        stamp = File.mtime(shared_file) + 1
        File.utime(stamp, stamp, shared_file)
      end

      it { is_expected.to eq(baseline) }
    end

    context "when a pre-loaded path cannot be read" do
      subject { [build.checksum, build.checksum] }

      # A directory the pattern matches: globbed like a file, but unreadable.
      before { Dir.mkdir(File.join(support_dir, "a_directory.rb")) }

      it "still counts it in, with a stable entry" do
        digest, reread = subject

        expect(digest).not_to eq(baseline)
        expect(reread).to eq(digest)
      end
    end

    context "when nothing is pre-loaded" do
      subject { build(patterns: []).checksum }

      it { is_expected.to be_nil }
    end
  end

  describe "#definitions" do
    subject { external_definitions.definitions(excluding: excluding) }

    let(:excluding) { nil }
    let(:external_definitions) { build }
    let(:shared_file) { File.join(support_dir, "shared.rb") }

    before do
      File.write(shared_file, <<~RUBY)
        RSpec.shared_examples "a thing" do
          it { expect(used).to eq(1) }
        end
      RUBY
    end

    it "returns the file's definition map" do
      expect(subject.first).to include("a thing")
    end

    context "when excluding matches a resolved path" do
      let(:excluding) { shared_file }

      it "omits it" do
        expect(subject).to eq([])
      end
    end

    context "when a pre-loaded file cannot be parsed" do
      before { File.write(shared_file, "def oops(") }

      it "skips it rather than raising" do
        expect(subject).to eq([])
      end
    end

    context "when the same file backs many calls" do
      subject { 3.times { external_definitions.definitions(excluding: excluding) } }

      before { allow(RuboCop::AST::ProcessedSource).to receive(:from_file).and_call_original }

      it "parses and indexes it once, reusing the cache" do
        subject

        expect(RuboCop::AST::ProcessedSource).to have_received(:from_file).once
      end
    end

    context "when a pre-loaded file is rewritten under its old mtime" do
      before do
        original_mtime = File.mtime(shared_file)
        external_definitions.definitions(excluding: excluding) # prime the cache
        File.write(shared_file, "#{File.read(shared_file)}# a comment that makes the file longer\n")
        File.utime(original_mtime, original_mtime, shared_file) # only the size gives the rewrite away
        allow(RuboCop::AST::ProcessedSource).to receive(:from_file).and_call_original
      end

      it "notices the rewrite and re-parses it" do
        subject

        expect(RuboCop::AST::ProcessedSource).to have_received(:from_file).once
      end
    end
  end
end
