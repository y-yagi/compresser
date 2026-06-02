# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in compresser.gemspec
gemspec

gem "irb"
gem "rake"
gem "minitest"

local_gemfile = File.expand_path(".Gemfile", __dir__)
instance_eval File.read local_gemfile if File.exist? local_gemfile
