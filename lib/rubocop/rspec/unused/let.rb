# frozen_string_literal: true

require "pathname"

require "rubocop"
require "rubocop-rspec"

require_relative "let/version"

module Rubocop
  module Rspec
    module Unused
      module Let
        class Error < StandardError; end

        PROJECT_ROOT =
          Pathname.new(__dir__ || ".").join("../../../..").expand_path.freeze
        CONFIG_DEFAULT = PROJECT_ROOT.join("config", "default.yml").freeze

        private_constant :PROJECT_ROOT
      end
    end
  end
end

require_relative "let/plugin"

require_relative "../../cop/rspec/unused_let"
