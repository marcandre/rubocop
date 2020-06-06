# frozen_string_literal: true

module RuboCop
  module Cop
    # A scaffold for concrete cops.
    #
    # The Cop::Base class is meant to be extended.
    #
    # Cops track offenses and can autocorrect them on the fly.
    #
    # A commissioner object is responsible for traversing the AST and invoking
    # the specific callbacks on each cop.
    #
    # First the callback `on_walk_begin` is called;
    # if a cop needs to do its own processing of the AST or depends on
    # something else.
    #
    # Then callbacks like `on_def`, `on_send` (see AST::Traversal) are called
    # with their respective nodes.
    #
    # Finally the callback `on_walk_end` is called.
    #
    # Within these callbacks, cops are meant to call `add_offense` or
    # `add_global_offense`. Use the `processed_source` method to
    # get the currently processed source being investigated.
    #
    # In case of invalid syntax / unparseable content,
    # the callback `on_other_file` is called instead of all the other
    # `on_...` callbacks.
    #
    # Private methods are not meant for custom cops consumption,
    # nor are any instance variables.
    #
    class Base # rubocop:disable Metrics/ClassLength
      extend RuboCop::AST::Sexp
      extend NodePattern::Macros
      include RuboCop::AST::Sexp
      include Util
      include IgnoredNode
      include AutocorrectLogic
      extend Cache

      attr_reader :config, :processed_source

      # @api private Reserved for Commissioner
      Investigation = Struct.new(:offenses, :corrector)

      # Call for abstract Cop classes
      def self.exclude_from_registry
        Registry.global.dismiss(self)
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
        reset_investigation
      end

      # Called before all on_... have been called
      # When refining this method, always call `super`
      def on_walk_begin
        # Typically do nothing here
      end

      # Called after all on_... have been called
      # When refining this method, always call `super`
      def on_walk_end
        # Typically do nothing here
      end

      # Called instead of all on_... callbacks for unrecognized files / syntax errors
      # When refining this method, always call `super`
      def on_other_file
        # Typically do nothing here
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

      # Override and return the Force class(es) you need to join
      def self.joining_forces
      end

      def message(_range = nil)
        self.class::MSG
      end

      def add_global_offense(message = nil, severity: nil)
        severity = find_severity(nil, severity)
        message = find_message(nil, message)
        @current_offenses <<
          Offense.new(severity, Offense::NO_LOCATION, message, name, :unsupported)
      end

      # Yields a corrector
      #
      def add_offense(node_or_range, message: nil, severity: nil, &block)
        range = range_from_node_or_range(node_or_range)
        return if duplicate_location?(range)

        range_to_pass = callback_argument(range)

        severity = find_severity(range_to_pass, severity)
        message = find_message(range_to_pass, message)

        status, corrector = enabled_line?(range.line) ? correct(range, &block) : :disabled

        @current_offenses << Offense.new(severity, range, message, name, status, corrector)
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
        file == RuboCop::AST::ProcessedSource::STRING_SOURCE_NAME ||
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

      def self.support_autocorrect?
        false
      end

      def self.inherited(subclass)
        Registry.global.enlist(subclass)
      end

      ### Make potential errors with previous API more obvious

      def offenses
        raise 'The offenses are not directly available; ' \
          'they are returned as the result of the investigation'
      end

      ### Reserved for Cop::Cop

      # @api private
      # Called between investigations
      def ready
        self
      end

      private

      ### Reserved for Cop::Cop

      def callback_argument(range)
        range
      end

      def apply_correction(corrector)
        @current_corrector&.merge!(corrector) if corrector
      end

      def correction_strategy
        return :unsupported unless correctable?
        return :uncorrected unless autocorrect?

        :attempt_correction
      end

      ### Reserved for Commissioner:

      # Called before any investigation
      def begin_investigation(processed_source)
        @current_offenses = []
        @currently_disabled_lines = {}
        @processed_source = processed_source
        @current_corrector = Corrector.new(@processed_source) if @processed_source.valid_syntax?
      end

      # Called to complete an investigation
      def complete_investigation
        Investigation.new(@current_offenses, @current_corrector)
      ensure
        reset_investigation
      end

      ### Actually private methods

      def reset_investigation
        @currently_disabled_lines = @current_offenses = @processed_source = @current_corrector = nil
      end

      def duplicate_location?(location)
        @current_offenses.any? { |o| o.location == location }
      end

      # @return [Symbol, Corrector] offense status
      def correct(range)
        status = correction_strategy

        if block_given?
          corrector = Corrector.new(self)
          yield corrector
          if !corrector.empty? && !self.class.support_autocorrect?
            raise "The Cop #{name} must `extend Autocorrector` to be able to autocorrect"
          end
        end

        status = attempt_correction(range, corrector) if status == :attempt_correction

        [status, corrector]
      end

      # @return [Symbol] offense status
      def attempt_correction(range, corrector)
        if corrector && !corrector.empty?
          status = :corrected
        elsif disable_uncorrectable?
          corrector = disable_uncorrectable(range)
          status = :corrected_with_todo
        else
          return :uncorrected
        end

        apply_correction(corrector) if corrector
        status
      end

      def disable_uncorrectable(range)
        line = range.line
        return if @currently_disabled_lines.key?(line)

        @currently_disabled_lines[line] = true
        disable_offense(range)
      end

      def range_from_node_or_range(node_or_range)
        if node_or_range.respond_to?(:loc)
          node_or_range.loc.expression
        elsif node_or_range.is_a?(::Parser::Source::Range)
          node_or_range
        else
          extra = ' (call `add_global_offense`)' if node_or_range.nil?
          raise "Expected a Source::Range, got #{node_or_range.inspect}#{extra}"
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
