# frozen_string_literal: true

require 'uri'
require_relative 'legacy/autocorrect_support'
require_relative 'legacy/corrections_support'

module RuboCop
  module Cop
    # A scaffold for concrete cops.
    #
    # The Cop class is meant to be extended.
    #
    # Cops track offenses and can autocorrect them on the fly.
    #
    # A commissioner object is responsible for traversing the AST and invoking
    # the specific callbacks on each cop.
    # If a cop needs to do its own processing of the AST or depends on
    # something else, it should define the `#investigate` method and do
    # the processing there.
    #
    # @example
    #
    #   class CustomCop < Cop
    #     def investigate(processed_source)
    #       # Do custom processing
    #     end
    #   end
    class Cop
      extend RuboCop::AST::Sexp
      extend NodePattern::Macros
      include RuboCop::AST::Sexp
      include Util
      include IgnoredNode
      include AutocorrectLogic
      prepend Legacy::AutocorrectSupport
      include Legacy::CorrectionsSupport::Cop

      attr_reader :config, :offenses
      attr_accessor :processed_source # TODO: Bad design.

      @registry = Registry.new

      class << self
        attr_reader :registry
      end

      def self.all
        registry.without_department(:Test).cops
      end

      def self.qualified_cop_name(name, origin)
        registry.qualified_cop_name(name, origin)
      end

      def self.inherited(subclass)
        registry.enlist(subclass)
      end

      def self.badge
        @badge ||= Badge.for(name)
      end

      def self.cop_name
        badge.to_s
      end

      def self.department
        badge.department
      end

      def self.lint?
        department == :Lint
      end

      # Returns true if the cop name or the cop namespace matches any of the
      # given names.
      def self.match?(given_names)
        return false unless given_names

        given_names.include?(cop_name) ||
          given_names.include?(department.to_s)
      end

      # List of cops that should not try to autocorrect at the same
      # time as this cop
      #
      # @return [Array<RuboCop::Cop::Cop>]
      #
      # @api public
      def self.autocorrect_incompatible_with
        []
      end

      def initialize(config = nil, options = nil)
        @config = config || Config.new
        @options = options || { debug: false }
        @legacy_argument = nil # See Legacy::AutocorrectSupport
        self.processed_source = nil
      end

      def processed_source=(processed_source)
        @offenses = []
        @processed_source = processed_source
        @corrector = Corrector.new(self) if processed_source
      end

      def join_force?(_force_class)
        false
      end

      def cop_config
        # Use department configuration as basis, but let individual cop
        # configuration override.
        @cop_config ||= @config.for_cop(self.class.department.to_s)
                               .merge(@config.for_cop(self))
      end

      def message(_range = nil)
        self.class::MSG
      end

      # Yields a corrector
      #
      def add_offense(node_or_range, message: nil, severity: nil, &block)
        range = _range_from_node_or_range(node_or_range)

        return if duplicate_location?(range)

        severity = find_severity(@legacy_argument || range, severity)
        message = find_message(@legacy_argument || range, message)

        status = enabled_line?(range.line) ? correct(range, &block) : :disabled

        @offenses << Offense.new(severity, range, message, name, status)
      end

      def duplicate_location?(location)
        @offenses.any? { |o| o.location == location }
      end

      def correct(range)
        status = correction_strategy(range)

        if block_given? && status != :disabled
          corrector = Corrector.new(self)
          # begin
            yield corrector
          # rescue StandardError => e
          #   raise ErrorWithAnalyzedFileLocation.new(
          #     cause: e, node: range, cop: self
          #   )
          # end
        end
        apply = case status
        when :corrected_with_todo
          disable_uncorrectable(range)
        when :corrected
          status = :uncorrected if corrector == nil || corrector.empty?
          corrector
        else
          # disregard corrector
        end

        @corrector.merge!(apply) if apply
        status
      end

      def correction_strategy(range)
        return :unsupported unless correctable?
        return :uncorrected unless autocorrect?

        if support_autocorrect?
          :corrected
        elsif disable_uncorrectable?
          :corrected_with_todo
        end
      end

      def disable_uncorrectable(range)
        @disabled_lines ||= {}
        line = range.line
        return if @disabled_lines.key?(line)

        @disabled_lines[line] = true
        disable_offense(range)
      end

      def config_to_allow_offenses
        Formatter::DisabledConfigFormatter
          .config_to_allow_offenses[cop_name] ||= {}
      end

      def config_to_allow_offenses=(hash)
        Formatter::DisabledConfigFormatter.config_to_allow_offenses[cop_name] =
          hash
      end

      def target_ruby_version
        @config.target_ruby_version
      end

      def target_rails_version
        @config.target_rails_version
      end

      def parse(source, path = nil)
        ProcessedSource.new(source, target_ruby_version, path)
      end

      def cop_name
        @cop_name ||= self.class.cop_name
      end

      alias name cop_name

      def relevant_file?(file)
        file_name_matches_any?(file, 'Include', true) &&
          !file_name_matches_any?(file, 'Exclude', false)
      end

      def excluded_file?(file)
        !relevant_file?(file)
      end

      # This method should be overridden when a cop's behavior depends
      # on state that lives outside of these locations:
      #
      #   (1) the file under inspection
      #   (2) the cop's source code
      #   (3) the config (eg a .rubocop.yml file)
      #
      # For example, some cops may want to look at other parts of
      # the codebase being inspected to find violations. A cop may
      # use the presence or absence of file `foo.rb` to determine
      # whether a certain violation exists in `bar.rb`.
      #
      # Overriding this method allows the cop to indicate to RuboCop's
      # ResultCache system when those external dependencies change,
      # ie when the ResultCache should be invalidated.
      def external_dependency_checksum
        nil
      end

      private

      # :nodoc:
      def _range_from_node_or_range(node_or_range)
        if node_or_range.respond_to?(:loc)
          node_or_range.loc.expression
        else
          node_or_range
        end
      end

      def find_message(range, message)
        annotate(message || message(range))
      end

      def annotate(message)
        RuboCop::Cop::MessageAnnotator.new(
          config, cop_name, cop_config, @options
        ).annotate(message)
      end

      def file_name_matches_any?(file, parameter, default_result)
        patterns = cop_config[parameter]
        return default_result unless patterns

        path = nil
        patterns.any? do |pattern|
          # Try to match the absolute path, as Exclude properties are absolute.
          next true if match_path?(pattern, file)

          # Try with relative path.
          path ||= config.path_relative_to_config(file)
          match_path?(pattern, path)
        end
      end

      def enabled_line?(line_number)
        return true if @options[:ignore_disable_comments] || !@processed_source

        @processed_source.comment_config.cop_enabled_at_line?(self, line_number)
      end

      def find_severity(_range, severity)
        custom_severity || severity || default_severity
      end

      def default_severity
        self.class.lint? ? :warning : :convention
      end

      def custom_severity
        severity = cop_config['Severity']
        return unless severity

        if Severity::NAMES.include?(severity.to_sym)
          severity.to_sym
        else
          message = "Warning: Invalid severity '#{severity}'. " \
            "Valid severities are #{Severity::NAMES.join(', ')}."
          warn(Rainbow(message).red)
        end
      end
    end
  end
end
