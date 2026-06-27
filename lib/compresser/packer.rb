# frozen_string_literal: true

require "rbconfig"
require "set"

module Compresser
  class Packer
    def initialize(gem_name, specs: nil, warn: true)
      @gem_name = gem_name
      @all_specs = specs
      @warn = warn
      @stdlib_paths = [
        RbConfig::CONFIG["rubylibdir"],
        RbConfig::CONFIG["sitelibdir"],
        RbConfig::CONFIG["vendorlibdir"],
      ].compact.uniq.select { |p| File.directory?(p) }
      Gem::Specification.find_by_name(gem_name) unless @all_specs
      @processed = {}
      @file_contents = {}
      @ordered = []
      @require_cache = {}
      @unresolved = {}
    end

    def pack
      main_file = resolve_require(@gem_name)
      raise Error, "Cannot find main file for gem '#{@gem_name}'" unless main_file

      process_file(main_file)
      generate_output
    end

    private

    def resolve_require(path)
      return @require_cache[path] if @require_cache.key?(path)

      (@all_specs || Gem::Specification).each do |spec|
        spec.full_require_paths.each do |load_path|
          candidate = File.join(load_path, "#{path}.rb")
          if File.exist?(candidate)
            return (@require_cache[path] = candidate)
          end
        end
      end

      @stdlib_paths.each do |load_path|
        candidate = File.join(load_path, "#{path}.rb")
        if File.exist?(candidate)
          return (@require_cache[path] = candidate)
        end
      end

      @require_cache[path] = nil
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

        if resolved
          process_file(resolved)
        else
          warn_unresolved(type, path)
        end
      end

      @ordered << file_path
    end

    def warn_unresolved(type, path)
      return unless @warn

      key = "#{type}:#{path}"
      return if @unresolved.key?(key)
      @unresolved[key] = true

      directive = type == :require_relative ? "require_relative" : "require"
      $stderr.puts "compresser: could not resolve #{directive} #{path.inspect}; leaving it as-is"
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
      dispatch_symbols = collect_component_symbols

      parts = []
      parts << "# frozen_string_literal: true\n\n" if has_frozen

      @ordered.each do |file_path|
        content = @file_contents[file_path]
        content = strip_magic_comments(content)
        content = strip_inlined_requires(content, file_path)
        content = resolve_static_send_calls(content)
        content = expand_dynamic_send_calls(content, dispatch_symbols)
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

    def collect_component_symbols
      array_syms = Set.new
      method_syms = Set.new

      @file_contents.each_value do |content|
        content.scan(/\[(?:\s*:[a-zA-Z_]\w*[?!]?\s*,?\s*)+\]/) do |arr|
          arr.scan(/:([a-zA-Z_]\w*[?!]?)/) { |m| array_syms << m[0].to_sym }
        end

        content.scan(/^\s*def (?:self\.)?([a-zA-Z_]\w*[?!=]?)(?:[ \t]*[(\n;]|$)/) do |m|
          method_syms << m[0].chomp("=").to_sym
        end
      end

      (array_syms & method_syms).reject { |s| s.to_s.end_with?("=") }.sort
    end

    def expand_dynamic_send_calls(content, symbols)
      return content if symbols.empty?

      # Compound: recv1.__send__("#{v}=", recv2.__send__(v)) — expand both in one case
      content = content.gsub(
        /([a-zA-Z_]\w*|self)\.(public_send|__send__)\("#\{([a-zA-Z_]\w*)\}=",\s*([a-zA-Z_]\w*)\.(public_send|__send__)\(\3\)\)/
      ) do
        r1  = Regexp.last_match(1)
        var = Regexp.last_match(3)
        r2  = Regexp.last_match(4)
        arms = symbols.map { |m| "when #{m.inspect} then #{r1}.#{m} = #{r2}.#{m}" }
        "(case #{var}; #{arms.join("; ")}; else raise ArgumentError, \"unknown component: \#{#{var}}\"; end)"
      end

      # Simple getter: recv.__send__(var) or recv.public_send(var)
      content = content.gsub(
        /([a-zA-Z_]\w*|self)\.(public_send|__send__)\(([a-zA-Z_]\w*)\)/
      ) do
        receiver = Regexp.last_match(1)
        var      = Regexp.last_match(3)
        arms = symbols.map { |m| "when #{m.inspect} then #{receiver}.#{m}" }
        "(case #{var}; #{arms.join("; ")}; else raise ArgumentError, \"unknown component: \#{#{var}}\"; end)"
      end

      content
    end

    def resolve_static_send_calls(content)
      content.gsub(/\.(public_send|__send__|send)\(:([a-zA-Z_]\w*[?!]?)((?:\s*,\s*(?:[^)(]|\([^)]*\))*)?)\)/) do
        method_name = Regexp.last_match(2)
        args_part = Regexp.last_match(3).strip
        if args_part.empty?
          ".#{method_name}"
        else
          ".#{method_name}(#{args_part.sub(/\A,\s*/, "")})"
        end
      end
    end

    def strip_inlined_requires(content, current_file)
      content
        .gsub(/^[ \t]*require_relative\s+['"]([^'"]+)['"][ \t]*(?:#[^\n]*)?(?:\n|\z)/) do |match|
          resolved = resolve_require_relative(Regexp.last_match(1), current_file)
          @processed.key?(resolved) ? "" : match
        end
        .gsub(/^[ \t]*require\s+['"]([^'"]+)['"][ \t]*(?:#[^\n]*)?(?:\n|\z)/) do |match|
          resolved = resolve_require(Regexp.last_match(1))
          @processed.key?(resolved) ? "" : match
        end
    end
  end
end
