# frozen_string_literal: true

module RuboCop
  module Cop
    # This module allows a more streamlined way to add an offense
    # and make a correction at once.
    #
    module Autocorrector
      # Yields a corrector
      #
      def add_offense(node_or_range, message: nil, severity: nil, &block)
        range = if node_or_range.respond_to?(:loc)
                  node_or_range.loc.expression
                else
                  node_or_range
                end
        @last_block = block
        super(range, location: range, message: message, severity: severity) do
          # This happens if @options[:auto_correct] is set to false
          _call_last_block(range) if @last_block
        end
      end

      # :nodoc:
      def autocorrect(range)
        return false unless @last_block

        our_corrector = _call_last_block(range)
        return false if our_corrector.empty?

        ->(corrector) { corrector.merge!(our_corrector) }
      end

      private

      # :nodoc:
      def _call_last_block(range)
        our_corrector = Corrector.new(processed_source.buffer)
        begin
          @last_block.call(our_corrector)
        rescue StandardError => e
          raise ErrorWithAnalyzedFileLocation.new(
            cause: e, node: range, cop: self
          )
        end
        @last_block = nil # Block already called, don't call twice
        our_corrector
      end
    end
  end
end
