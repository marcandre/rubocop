# frozen_string_literal: true

require 'tempfile'

# This module provides methods that make it easier to test Cops.
module CopHelper
  extend RSpec::SharedContext

  let(:ruby_version) { 2.4 }
  let(:rails_version) { false }

  let(:source) { 'code = {some: :ruby}' }

  let(:processed_source) { parse_source(source, 'test') }

  let(:source_buffer) { processed_source.buffer }

  let(:cop_class) do
    described_class.is_a?(Class) && described_class < RuboCop::Cop::Cop ?
      described_class : RuboCop::Cop::Cop
  end

  let(:options) { {} }

  let(:config) { RuboCop::Config.new({}) }

  let(:cop) do
    cop_class.new(config, options)
    .tap { |cop| cop.processed_source = processed_source }
  end

  def source_range(buffer = source_buffer, range)
    Parser::Source::Range.new(buffer, range.begin,
      range.exclude_end? ? range.end : range.end+1)
  end

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

    corrector =
      RuboCop::Cop::Corrector.new(processed_source.buffer, cop.corrections)
    corrector.rewrite
  end

  def autocorrect_source_with_loop(source, file = nil)
    cnt = 0
    loop do
      cop.instance_variable_set(:@corrections, [])
      new_source = autocorrect_source(source, file)
      return new_source if new_source == source

      source = new_source
      cnt += 1
      raise RuboCop::Runner::InfiniteCorrectionLoop.new(file, []) if cnt > RuboCop::Runner::MAX_ITERATIONS
    end
  end

  def _investigate(cop, processed_source)
    forces = RuboCop::Cop::Force.all.each_with_object([]) do |klass, instances|
      next unless cop.join_force?(klass)

      instances << klass.new([cop])
    end

    commissioner =
      RuboCop::Cop::Commissioner.new([cop], forces, raise_error: true)
    commissioner.investigate(processed_source)
    commissioner
  end
end

module RuboCop
  module Cop
    # Monkey-patch Cop for tests to provide easy access to messages and
    # highlights.
    class Cop
      def messages
        offenses.sort.map(&:message)
      end

      def highlights
        offenses.sort.map { |o| o.location.source }
      end
    end
  end
end
