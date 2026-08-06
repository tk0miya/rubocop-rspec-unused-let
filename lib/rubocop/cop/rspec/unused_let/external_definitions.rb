# frozen_string_literal: true

require "digest"

require_relative "shared_example_registry"

module RuboCop
  module Cop
    module RSpec
      class UnusedLet < ::RuboCop::Cop::RSpec::Base
        # The `SharedExamplePaths` patterns resolved to file contents: the
        # absolute paths they expand to, a result-cache checksum covering them,
        # and their parsed definition maps for {SharedExampleRegistry}'s external
        # fallback.
        class ExternalDefinitions
          # @rbs!
          #   type cache_key = [ Time, Integer ]
          #   type cache_entry = [ cache_key, SharedExampleRegistry::definition_mapping? ]

          # @rbs self.@default_cache: Hash[String, cache_entry]?

          # Process-wide cache of the external files' definition maps, keyed by
          # absolute path to `[[mtime, size], definitions | nil]`. Used as the
          # default so a support file shared by many specs is scanned once per
          # process, not once per spec (RuboCop builds a fresh cop instance per
          # inspected file).
          def self.default_cache #: Hash[String, cache_entry]
            @default_cache ||= {}
          end

          # @rbs patterns: Array[String]
          # @rbs base_dir: String
          # @rbs target_ruby_version: Numeric
          # @rbs cache: Hash[String, cache_entry]
          def initialize(patterns:, base_dir:, target_ruby_version:, cache: self.class.default_cache) #: void
            @patterns = patterns
            @base_dir = base_dir
            @target_ruby_version = target_ruby_version
            @cache = cache
          end

          # The absolute paths the patterns expand to, in a stable order. Not
          # cached on the instance: a `--server` process outlives a run, so a
          # cached expansion would go on ignoring later additions.
          def paths #: Array[String]
            patterns
              .flat_map { Dir.glob(File.expand_path(_1, base_dir)) }
              .map { File.expand_path(_1) }
              .uniq
              .sort
          end

          # The paths' digest for RuboCop's result-cache key, which otherwise
          # covers no project file but the inspected one. `nil` when there is
          # nothing to pre-load.
          def checksum #: String?
            found = paths
            return nil if found.empty?

            Digest::SHA1.hexdigest(found.map { file_signature(_1) }.join("\n"))
          end

          # The paths' definition maps, excluding `excluding` so the file under
          # investigation is never indexed twice.
          #
          # @rbs excluding: String?
          def definitions(excluding:) #: Array[SharedExampleRegistry::definition_mapping]
            current = File.expand_path(excluding) if excluding
            paths.reject { _1 == current }.filter_map { definitions_for(_1) }
          end

          private

          attr_reader :patterns #: Array[String]
          attr_reader :base_dir #: String
          attr_reader :target_ruby_version #: Numeric
          attr_reader :cache #: Hash[String, cache_entry]

          # `path`'s identity for the result-cache digest. Content rather than
          # mtime, which git does not preserve: keying on it would let a checkout
          # discard a persisted cache wholesale. An unreadable path still gets a
          # stable entry rather than breaking the run.
          #
          # @rbs path: String
          def file_signature(path) #: String
            "#{path}:#{Digest::SHA1.file(path).hexdigest}"
          rescue SystemCallError
            "#{path}:"
          end

          # The cached definition map for one external file, or `nil` when it
          # cannot be read or parsed — in which case the cop stays conservative
          # rather than crashing the run.
          #
          # @rbs path: String
          def definitions_for(path) #: SharedExampleRegistry::definition_mapping?
            stat = File.stat(path)
            key = [stat.mtime, stat.size] #: cache_key
            cached = cache[path]
            return cached.last if cached && cached.first == key

            definitions = build_definitions_for(path)
            cache[path] = [key, definitions]
            definitions
          rescue SystemCallError
            nil
          end

          # @rbs path: String
          def build_definitions_for(path) #: SharedExampleRegistry::definition_mapping?
            ast = RuboCop::AST::ProcessedSource.from_file(path, target_ruby_version).ast
            ast && SharedExampleRegistry.new(ast).local_definitions
          rescue RuboCop::Error, SystemCallError
            nil
          end
        end
      end
    end
  end
end
