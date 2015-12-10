require 'ladle/file_filter'

module Ladle
  class StewardChangesView
    attr_reader :stewards_file, :file_filter, :changes

    def initialize(stewards_file:, file_filter: nil, changes: nil)
      @file_filter   = file_filter || FileFilter.new
      @stewards_file = Pathname.new(stewards_file)
      @changes       = changes || []
    end

    def empty?
      @changes.empty?
    end

    def add_file_changes(file_changes)
      file_changes.each do |file_change|
        if @file_filter.include?(file_change.file.relative_path_from(@stewards_file.dirname))
          @changes << file_change
        end
      end
    end

    def ==(other)
      @stewards_file.to_s == other.stewards_file.to_s &&
        @file_filter == other.file_filter &&
        @changes.to_set == other.changes.to_set
    end

    def hash
      [@stewards_file, @file_filter, @changes].hash
    end

    alias eql? ==
  end
end
