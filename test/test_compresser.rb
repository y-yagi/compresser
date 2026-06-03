# frozen_string_literal: true

require "test_helper"

FakeSpec = Struct.new(:name, :full_require_paths)

class TestCompresser < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Compresser::VERSION
  end

  def test_pack_produces_single_file
    result = Compresser::Packer.new("compresser", warn: false).pack
    assert_kind_of String, result
    assert_includes result, "module Compresser"
  end

  def test_pack_has_frozen_string_literal
    result = Compresser::Packer.new("compresser", warn: false).pack
    assert result.start_with?("# frozen_string_literal: true")
  end

  def test_pack_strips_internal_requires
    result = Compresser::Packer.new("compresser", warn: false).pack
    refute_match(/^require_relative\s+["']compresser/, result)
    refute_match(/^require\s+["']compresser\//, result)
  end

  def test_pack_raises_for_missing_gem
    assert_raises(Gem::MissingSpecError) do
      Compresser::Packer.new("nonexistent_gem_xyz_123").pack
    end
  end
end

class TestPackerWithFixtures < Minitest::Test
  FIXTURES_DIR = File.join(__dir__, "fixtures")

  def fixture_spec(name)
    FakeSpec.new(name, [File.join(FIXTURES_DIR, name, "lib")])
  end

  def packer(gem_name, *dep_names)
    specs = [gem_name, *dep_names].map { |n| fixture_spec(n) }
    Compresser::Packer.new(gem_name, specs: specs, warn: false)
  end

  def test_pack_inlines_external_gem
    result = packer("gem_a", "gem_b").pack
    assert_includes result, "module GemA"
    assert_includes result, "module GemB"
  end

  def test_pack_preserves_unresolvable_requires
    # this lib is not present in the injected specs nor the stdlib, so it stays as require
    result = packer("gem_b").pack
    assert_match(/^require "external_unresolvable_lib"/, result)
  end

  def test_pack_inlines_stdlib_require
    result = packer("gem_with_stdlib").pack
    refute_match(/^require "pathname"/, result)
    assert_includes result, "class Pathname"
  end

  def test_pack_preserves_c_extension_require
    # io/wait has no .rb file; only a C extension, so it cannot be inlined
    result = packer("gem_with_stdlib").pack
    assert_match(/^require "io\/wait"/, result)
  end

  def test_pack_stdlib_appears_before_dependent
    result = packer("gem_with_stdlib").pack
    pathname_pos = result.index("class Pathname")
    gem_pos = result.index("module GemWithStdlib")
    assert pathname_pos < gem_pos, "Pathname must appear before GemWithStdlib"
  end

  def test_pack_strips_inlined_gem_requires
    result = packer("gem_a", "gem_b").pack
    refute_match(/^require "gem_b"/, result)
    refute_match(/^require "gem_a\//, result)
  end

  def test_pack_shared_dependency_included_once
    # gem_a/core.rb also requires gem_a/shared, so shared would be required twice
    result = packer("gem_a", "gem_b").pack
    assert_equal 1, result.scan("module GemA\n  module Shared").length
  end

  def test_pack_dependency_appears_before_dependent
    result = packer("gem_a", "gem_b").pack
    gem_b_pos = result.index("module GemB")
    gem_a_pos = result.rindex("module GemA")
    assert gem_b_pos < gem_a_pos, "GemB must appear before GemA"
  end

  def test_pack_frozen_string_literal_appears_once
    result = packer("gem_a", "gem_b").pack
    assert_equal 1, result.scan("# frozen_string_literal: true").length
  end

  def test_pack_handles_circular_dependency
    result = packer("gem_circular").pack
    assert_includes result, "module GemCircular"
    assert_includes result, "module A"
    assert_includes result, "module B"
  end

  def test_pack_circular_dependency_each_file_once
    result = packer("gem_circular").pack
    assert_equal 1, result.scan("module GemCircular\n  module A").length
    assert_equal 1, result.scan("module GemCircular\n  module B").length
  end
end
