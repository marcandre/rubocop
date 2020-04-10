# frozen_string_literal: true

module RuboCop
  module Cop
    # Error raised when an unqualified cop name is used that could
    # refer to two or more cops under different departments
    class AmbiguousCopName < RuboCop::Error
      MSG = 'Ambiguous cop name `%<name>s` used in %<origin>s needs ' \
            'department qualifier. Did you mean %<options>s?'

      def initialize(name, origin, badges)
        super(
          format(
            MSG,
            name: name,
            origin: origin,
            options: badges.to_a.join(' or ')
          )
        )
      end
    end

    # Registry that tracks all cops by their badge and department.
    class Registry
      def initialize(cops = [], options = {})
        @registry = {}
        @departments = {}
        @cops_by_cop_name = Hash.new { |hash, key| hash[key] = [] }

        cops.each { |cop| enlist(cop) }
        @options = options
      end

      def enlist(cop)
        @registry[cop.badge] = cop
        @departments[cop.department] ||= []
        @departments[cop.department] << cop
        @cops_by_cop_name[cop.cop_name] << cop
      end

      # @return [Array<Symbol>] list of departments for current cops.
      def departments
        @departments.keys
      end

      # @return [Registry] Cops for that specific department.
      def with_department(department)
        with(@departments.fetch(department, []))
      end

      # @return [Registry] Cops not for a specific department.
      def without_department(department)
        without_department = @departments.dup
        without_department.delete(department)

        with(without_department.values.flatten)
      end

      def contains_cop_matching?(names)
        cops.any? { |cop| cop.match?(names) }
      end

      # Convert a user provided cop name into a properly namespaced name
      #
      # @example gives back a correctly qualified cop name
      #
      #   cops = RuboCop::Cop::Cop.all
      #   cops.
      #     qualified_cop_name('Layout/EndOfLine') # => 'Layout/EndOfLine'
      #
      # @example fixes incorrect namespaces
      #
      #   cops = RuboCop::Cop::Cop.all
      #   cops.qualified_cop_name('Lint/EndOfLine') # => 'Layout/EndOfLine'
      #
      # @example namespaces bare cop identifiers
      #
      #   cops = RuboCop::Cop::Cop.all
      #   cops.qualified_cop_name('EndOfLine') # => 'Layout/EndOfLine'
      #
      # @example passes back unrecognized cop names
      #
      #   cops = RuboCop::Cop::Cop.all
      #   cops.qualified_cop_name('NotACop') # => 'NotACop'
      #
      # @param name [String] Cop name extracted from config
      # @param path [String, nil] Path of file that `name` was extracted from
      #
      # @raise [AmbiguousCopName]
      #   if a bare identifier with two possible namespaces is provided
      #
      # @note Emits a warning if the provided name has an incorrect namespace
      #
      # @return [String] Qualified cop name
      def qualified_cop_name(name, path, shall_warn = true)
        badge = Badge.parse(name)
        print_warning(name, path) if shall_warn && department_missing?(badge, name)
        return name if registered?(badge)

        potential_badges = qualify_badge(badge)

        case potential_badges.size
        when 0 then name # No namespace found. Deal with it later in caller.
        when 1 then resolve_badge(badge, potential_badges.first, path)
        else raise AmbiguousCopName.new(badge, path, potential_badges)
        end
      end

      def department_missing?(badge, name)
        !badge.qualified? && unqualified_cop_names.include?(name)
      end

      def print_warning(name, path)
        message = "#{path}: Warning: no department given for #{name}."
        if path.end_with?('.rb')
          message += ' Run `rubocop -a --only Migration/DepartmentName` to fix.'
        end
        warn message
      end

      def unqualified_cop_names
        @unqualified_cop_names ||=
          Set.new(@cops_by_cop_name.keys.map { |qn| File.basename(qn) }) <<
          'RedundantCopDisableDirective'
      end

      # @return [Hash{String => Array<Class>}]
      def to_h
        @cops_by_cop_name
      end

      def cops
        @registry.values
      end

      def length
        @registry.size
      end

      def enabled(config, only, only_safe = false)
        select do |cop|
          only.include?(cop.cop_name) || enabled?(cop, config, only_safe)
        end
      end

      def enabled?(cop, config, only_safe)
        cfg = config.for_cop(cop)

        cop_enabled = cfg.fetch('Enabled') == true ||
                      enabled_pending_cop?(cfg, config)

        if only_safe
          cop_enabled && cfg.fetch('Safe', true)
        else
          cop_enabled
        end
      end

      def enabled_pending_cop?(cop_cfg, config)
        return false if @options[:disable_pending_cops]

        cop_cfg.fetch('Enabled') == 'pending' &&
          (@options[:enable_pending_cops] || config.enabled_new_cops?)
      end

      def names
        cops.map(&:cop_name)
      end

      def ==(other)
        cops == other.cops
      end

      def sort!
        @registry = Hash[@registry.sort_by { |badge, _| badge.cop_name }]

        self
      end

      def select(&block)
        cops.select(&block)
      end

      def each(&block)
        cops.each(&block)
      end

      # @param [String] cop_name
      # @return [Class, nil]
      def find_by_cop_name(cop_name)
        @cops_by_cop_name[cop_name].first
      end

      @global = new

      class << self
        attr_reader :global
      end

      def self.all
        global.without_department(:Test).cops
      end

      def self.qualified_cop_name(name, origin)
        global.qualified_cop_name(name, origin)
      end

      private

      def with(cops)
        self.class.new(cops)
      end

      def qualify_badge(badge)
        @departments
          .map { |department, _| badge.with_department(department) }
          .select { |potential_badge| registered?(potential_badge) }
      end

      def resolve_badge(given_badge, real_badge, source_path)
        unless given_badge.match?(real_badge)
          path = PathUtil.smart_path(source_path)
          warn "#{path}: #{given_badge} has the wrong namespace - " \
               "should be #{real_badge.department}"
        end

        real_badge.to_s
      end

      def registered?(badge)
        @registry.key?(badge)
      end
    end
  end
end
