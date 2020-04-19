# frozen_string_literal: true

module RuboCop
  module Cop
    # This class takes a source buffer and rewrite its source
    # based on the different correction rules supplied.
    #
    # Important!
    # The nodes modified by the corrections should be part of the
    # AST of the source_buffer.
    class Corrector < ::Parser::Source::TreeRewriter
      # Legacy support for Corrector#corrections
      # Used to be an array of lambdas to be called on a corrector
      class CorrectionsProxy
        def initialize(corrector)
          @corrector = corrector
        end

        def <<(callable)
          @corrector.transaction do
            callable.call(@corrector)
          end
        rescue ErrorWithAnalyzedFileLocation => e
          # ignore Clobbering errors
          raise e unless e.cause.is_a?(::Parser::ClobberingError)
        end

        def empty?
          @corrector.empty?
        end

        def concat(corrections)
          corrections.each { |correction| self << correction }
        end

        protected

        attr_reader :corrector
      end

      # @param source_buffer [Parser::Source::Buffer]
      # @param corrections [Array(#call)]
      #   This is deprecated.
      #   Array of Objects that respond to #call. They will receive the
      #   corrector itself and should use its method to modify the source.
      #
      #   corrector = Corrector.new(source_buffer)
      def initialize(source_buffer, corr = [])
        raise 'source_buffer should be a Parser::Source::Buffer' unless \
          source_buffer.is_a? Parser::Source::Buffer

        super(
          source_buffer,
          different_replacements: :raise,
          swallowed_insertions: :raise,
          crossing_deletions: :accept
        )

        # Don't print warnings to stderr if corrections conflict with each other
        diagnostics.consumer = ->(diagnostic) {}

        # Support legacy argument
        corr.each do |c|
          corrections << c
        end
      end

      alias rewrite process # Legacy

      def corrections
        CorrectionsProxy.new(self)
      end

      # Inserts new code before the given source range.
      #
      # @param [Parser::Source::Range, Rubocop::AST::Node] range or node
      # @param [String] content
      def insert_before(node_or_range, content)
        range = to_range(node_or_range)
        # TODO: Fix Cops using bad ranges instead
        if range.end_pos > @source_buffer.source.size
          range = range.with(end_pos: @source_buffer.source.size)
        end
        super(range, content)
      end

      # Removes `size` characters prior to the source range.
      #
      # @param [Parser::Source::Range, Rubocop::AST::Node] range or node
      # @param [Integer] size
      def remove_preceding(node_or_range, size)
        range = to_range(node_or_range)
        to_remove = range.with(
          begin_pos: range.begin_pos - size,
          end_pos:   range.begin_pos
        )
        remove(to_remove)
      end

      # Removes `size` characters from the beginning of the given range.
      # If `size` is greater than the size of `range`, the removed region can
      # overrun the end of `range`.
      #
      # @param [Parser::Source::Range, Rubocop::AST::Node] range or node
      # @param [Integer] size
      def remove_leading(node_or_range, size)
        range = to_range(node_or_range)
        to_remove = range.with(end_pos: range.begin_pos + size)
        remove(to_remove)
      end

      # Removes `size` characters from the end of the given range.
      # If `size` is greater than the size of `range`, the removed region can
      # overrun the beginning of `range`.
      #
      # @param [Parser::Source::Range, Rubocop::AST::Node] range or node
      # @param [Integer] size
      def remove_trailing(node_or_range, size)
        range = to_range(node_or_range)
        to_remove = range.with(begin_pos: range.end_pos - size)
        remove(to_remove)
      end

      private

      # :nodoc:
      def to_range(node_or_range)
        range = case node_or_range
                when ::RuboCop::AST::Node, ::Parser::Source::Comment
                  node_or_range.loc.expression
                when ::Parser::Source::Range
                  node_or_range
                else
                  raise TypeError,
                        'Expected a Parser::Source::Range, Comment or ' \
                        "Rubocop::AST::Node, got #{node_or_range.class}"
                end
        validate_buffer(range.source_buffer)
        range
      end

      def check_range_validity(node_or_range)
        super(to_range(node_or_range))
      end

      def validate_buffer(buffer)
        return if buffer == source_buffer

        unless buffer.is_a?(::Parser::Source::Buffer)
          # actually this should be enforced by parser gem
          raise 'Corrector expected range source buffer to be a ' \
                "Parser::Source::Buffer, but got #{buffer.class}"
        end
        raise "Correction target buffer #{buffer.object_id} " \
              "name:#{buffer.name.inspect}" \
              " is not current #{@source_buffer.object_id} " \
              "name:#{@source_buffer.name.inspect} under investigation"
      end
    end
  end
end
