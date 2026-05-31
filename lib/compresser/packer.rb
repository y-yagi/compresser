# frozen_string_literal: true

module Compresser
  class Packer
    def initialize(gem_name)
      @gem_name = gem_name
      @spec = Gem::Specification.find_by_name(gem_name)
      @load_paths = @spec.load_paths
      @processed = {}
      @file_contents = {}
      @ordered = []
    end

    def pack
      main_file = resolve_require(@gem_name)
      raise Error, "Cannot find main file for gem '#{@gem_name}'" unless main_file

      process_file(main_file)
      generate_output
    end

    private

    def resolve_require(path)
      @load_paths.each do |load_path|
        candidate = File.join(load_path, "#{path}.rb")
        return candidate if File.exist?(candidate)
      end
      nil
    end

    def resolve_require_relative(path, current_file)
      base = File.expand_path(path, File.dirname(current_file))
      candidate = "#{base}.rb"
      return candidate if File.exist?(candidate)
      return base if File.exist?(base)
      nil
    end

    def process_file(file_path)
      return if @processed.key?(file_path)
      @processed[file_path] = true

      content = File.read(file_path)
      @file_contents[file_path] = content

      extract_requires(content).each do |type, path|
        resolved = if type == :require_relative
          resolve_require_relative(path, file_path)
        else
          resolve_require(path)
        end

        process_file(resolved) if resolved
      end

      @ordered << file_path
    end

    def extract_requires(content)
      requires = []
      content.each_line do |line|
        next if line.strip.start_with?("#")

        if (m = line.match(/^\s*require_relative\s+['"]([^'"]+)['"]/))
          requires << [:require_relative, m[1]]
        elsif (m = line.match(/^\s*require\s+['"]([^'"]+)['"]/))
          requires << [:require, m[1]]
        end
      end
      requires
    end

    def generate_output
      has_frozen = @file_contents.values.any? { |c| c.include?("# frozen_string_literal: true") }

      parts = []
      parts << "# frozen_string_literal: true\n\n" if has_frozen

      @ordered.each do |file_path|
        content = @file_contents[file_path]
        content = strip_magic_comments(content)
        content = strip_inlined_requires(content, file_path)
        content = content.strip
        next if content.empty?

        parts << content
        parts << "\n\n"
      end

      parts.join.rstrip + "\n"
    end

    def strip_magic_comments(content)
      content
        .gsub(/^# frozen_string_literal: (?:true|false)\n/, "")
        .gsub(/^# encoding: .*\n/, "")
        .gsub(/^# coding: .*\n/, "")
    end

    def strip_inlined_requires(content, current_file)
      content
        .gsub(/^[ \t]*require_relative\s+['"]([^'"]+)['"]\s*\n?/) do |match|
          resolved = resolve_require_relative(Regexp.last_match(1), current_file)
          @processed.key?(resolved) ? "" : match
        end
        .gsub(/^[ \t]*require\s+['"]([^'"]+)['"]\s*\n?/) do |match|
          resolved = resolve_require(Regexp.last_match(1))
          @processed.key?(resolved) ? "" : match
        end
    end
  end
end
