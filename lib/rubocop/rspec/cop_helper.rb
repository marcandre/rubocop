# frozen_string_literal: true

require 'tempfile'

# This module provides methods that make it easier to test Cops.
module CopHelper
  extend RSpec::SharedContext

  let(:ruby_version) { 2.4 }
  let(:rails_version) { false }

  def inspect_source_file(source)
    Tempfile.open('tmp') { |f| inspect_source(source, f) }
  end

  def inspect_source(source, file = nil)
    RuboCop::Formatter::DisabledConfigFormatter.config_to_allow_offenses = {}
    RuboCop::Formatter::DisabledConfigFormatter.detected_styles = {}
    processed_source = parse_source(source, file)
    raise 'Error parsing example code' unless processed_source.valid_syntax?

    _investigate(cop, processed_source)
  end

  def parse_source(source, file = nil)
    if file&.respond_to?(:write)
      file.write(source)
      file.rewind
      file = file.path
    end

    RuboCop::ProcessedSource.new(source, ruby_version, file)
  end

  def autocorrect_source_file(source)
    Tempfile.open('tmp') { |f| autocorrect_source(source, f) }
  end

  def autocorrect_source(source, file = nil)
    RuboCop::Formatter::DisabledConfigFormatter.config_to_allow_offenses = {}
    RuboCop::Formatter::DisabledConfigFormatter.detected_styles = {}
    cop.instance_variable_get(:@options)[:auto_correct] = true
    processed_source = parse_source(source, file)
    _investigate(cop, processed_source)

    cop.current_corrector.rewrite
  end

  def autocorrect_source_with_loop(source, file = nil)
    cnt = 0
    loop do
      cop.instance_variable_set(:@corrections, [])
      new_source = autocorrect_source(source, file)
      return new_source if new_source == source

      source = new_source
      cnt += 1
      if cnt > RuboCop::Runner::MAX_ITERATIONS
        raise RuboCop::Runner::InfiniteCorrectionLoop.new(file, [])
      end
    end
  end

  def _investigate(cop, processed_source)
    team = RuboCop::Cop::Team.new([cop], nil, raise_error: true)
    team.inspect_file(processed_source)
  end
end

module RuboCop
  module Cop
    # Monkey-patch Cop for tests to provide easy access to messages and
    # highlights.
    class Base
      def messages
        offenses.sort.map(&:message)
      end

      def highlights
        offenses.sort.map { |o| o.location.source }
      end
    end
  end
end
