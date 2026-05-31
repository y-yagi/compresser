# frozen_string_literal: true

require "test_helper"

class TestCompresser < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Compresser::VERSION
  end

  def test_pack_produces_single_file
    result = Compresser::Packer.new("compresser").pack
    assert_kind_of String, result
    assert_includes result, "module Compresser"
  end

  def test_pack_has_frozen_string_literal
    result = Compresser::Packer.new("compresser").pack
    assert result.start_with?("# frozen_string_literal: true")
  end

  def test_pack_strips_internal_requires
    result = Compresser::Packer.new("compresser").pack
    refute_match(/^require_relative\s+["']compresser/, result)
    refute_match(/^require\s+["']compresser\//, result)
  end

  def test_pack_raises_for_missing_gem
    assert_raises(Gem::MissingSpecError) do
      Compresser::Packer.new("nonexistent_gem_xyz_123").pack
    end
  end
end
