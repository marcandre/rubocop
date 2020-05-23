# frozen_string_literal: true

module RuboCop
  module Cop
    # This class takes a source buffer and rewrite its source
    # based on the different correction rules supplied.
    #
    # Important!
    # The nodes modified by the corrections should be part of the
    # AST of the source_buffer.
    class Rewriter < ::Parser::Source::TreeRewriter
      # @param source [Parser::Source::Buffer, or anything
      #                leading to one via `(processed_source.)buffer`]
      #
      #   corrector = Corrector.new(cop)
      def initialize(source)
        source = source.processed_source if source.respond_to?(:processed_source)
        source = source.buffer if source.respond_to?(:buffer)

        unless source.is_a? Parser::Source::Buffer
          raise TypeError, 'Expected argument to lead to a Parser::Source::Buffer ' \
                           "but got #{source.inspect}"
        end

        super(
          source,
          different_replacements: :raise,
          swallowed_insertions: :raise,
          crossing_deletions: :accept
        )

        # Don't print warnings to stderr if corrections conflict with each other
        diagnostics.consumer = ->(diagnostic) {}
      end

      alias rewrite process # Legacy

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

    module Legacy
      class Corrector < Rewriter
        # Support legacy second argument
        def initialize(source, corr = [])
          super(source)
          if corr.is_a?(CorrectionsProxy)
            merge!(corr.send(:corrector))
          else
            # warn "Corrector.new with corrections is deprecated." unless corr.empty? TODO
            corr.each do |c|
              corrections << c
            end
          end
        end

        def corrections
          # warn "#corrections is deprecated. Open an issue if you have a valid usecase." TODO
          CorrectionsProxy.new(self)
        end
      end
    end

    Corrector = Legacy::Corrector # for the time being
  end
end
