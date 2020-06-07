# frozen_string_literal: true

module RuboCop
  module Cop
    # Common functionality for handling percent literal delimiters.
    class PreferredDelimiters
      extend FastArray::Function

      attr_reader :type, :config

      PERCENT_LITERAL_TYPES = FastArray %w[% %i %I %q %Q %r %s %w %W %x]

      def initialize(type, config, preferred_delimiters)
        @type = type
        @config = config
        @preferred_delimiters = preferred_delimiters
      end

      def delimiters
        preferred_delimiters[type].split(//)
      end

      private

      def ensure_valid_preferred_delimiters
        invalid = preferred_delimiters_config.keys -
                  (PERCENT_LITERAL_TYPES + %w[default])
        return if invalid.empty?

        raise ArgumentError,
              "Invalid preferred delimiter config key: #{invalid.join(', ')}"
      end

      def preferred_delimiters
        @preferred_delimiters ||=
          begin
            ensure_valid_preferred_delimiters

            if preferred_delimiters_config.key?('default')
              Hash[PERCENT_LITERAL_TYPES.map do |type|
                [type, preferred_delimiters_config[type] ||
                  preferred_delimiters_config['default']]
              end]
            else
              preferred_delimiters_config
            end
          end
      end

      def preferred_delimiters_config
        config.for_cop('Style/PercentLiteralDelimiters')['PreferredDelimiters']
      end
    end
  end
end
