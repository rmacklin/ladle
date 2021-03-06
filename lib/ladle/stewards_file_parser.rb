require 'ladle/stewards_file'
require 'ladle/steward_config'

require 'psych'

module Ladle
  class StewardsFileParser
    class ParsingError < StandardError
    end

    def self.parse(contents)
      raise ParsingError, "Cannot parse empty file" if contents.blank?

      yaml_contents = Psych.load(contents)
      raise ParsingError, "Stewards file must contain a hash" unless yaml_contents.is_a?(Hash)

      stewards = (yaml_contents["stewards"] || []).map do |config|
        github_username = config
        include_patterns = []
        exclude_patterns = []

        if config.is_a?(Hash)
          github_username = config["github_username"]
          include_patterns = config["include"]
          exclude_patterns = config["exclude"]
        end

        raise ParsingError, "Missing required key: github_username" if github_username.blank?

        StewardConfig.new(github_username: github_username, include_patterns: include_patterns, exclude_patterns: exclude_patterns)
      end

      StewardsFile.new(stewards)
    rescue Psych::SyntaxError
      raise ParsingError, "Failed parsing file"
    end
  end
end
