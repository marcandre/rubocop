# frozen_string_literal: true

module RuboCop
  module Cop
    module Legacy
      # Legacy support for Cop#autocorrect
      # See manual/cop_api_v1_changelog.md
      module AutocorrectSupport
        # Extension for Cop::Corrector
        module Corrector
          # Copy legacy v0 setting from cop
          def initialize(source, *)
            source = _fix_source(source)
            super
          end

          # Inserts new code before the given source range.
          #
          # @param [Parser::Source::Range, Rubocop::AST::Node] range or node
          # @param [String] content
          def insert_before(node_or_range, content)
            return super if @v1_support

            range = to_range(node_or_range)
            # TODO: Fix Cops using bad ranges instead
            if range.end_pos > @source_buffer.source.size
              range = range.with(end_pos: @source_buffer.source.size)
            end
            super(range, content)
          end

          private

          def _fix_source(source)
            @v1_support = source.is_a?(Cop) && source.class.v1_support?
            return source unless source.is_a?(Cop) && source.processed_source.nil?

            # warn "Calling add_offense on a cop that doesn't have a processed buffer is deprecated"
            ::Parser::Source::Buffer.new('bogus').tap { |b| b.source = '' }
          end
        end

        # Extension for Cop::Cop
        module Cop
          Correction = Struct.new(:lambda, :node, :cop) do
            def call(corrector)
              lambda.call(corrector)
            rescue StandardError => e
              raise ErrorWithAnalyzedFileLocation.new(
                cause: e, node: node, cop: cop
              )
            end
          end

          def add_offense(node_or_range, location: :expression, message: nil, severity: nil, &block)
            if self.class.v1_support?
              unless location == :expression
                raise 'Parameter location is not supported with the new API;' \
                      'pass the node or range as first argument'
              end
              super(node_or_range, message: message, severity: severity)
            else
              @v0_argument = node_or_range
              range = find_location(node_or_range, location)
              if block.nil? && !autocorrect?
                super(range, message: message, severity: severity)
              else
                super(range, message: message, severity: severity) do |corrector|
                  _emulate_v0_callsequence(corrector, &block)
                end
              end
            end
          end

          def find_location(node, loc)
            warn 'deprecated' if self.class.v1_support?
            # Location can be provided as a symbol, e.g.: `:keyword`
            loc.is_a?(Symbol) ? node.loc.public_send(loc) : loc
          end

          def support_autocorrect?
            # warn 'deprecated, use cop.class.support_autocorrect?' TODO
            self.class.support_autocorrect?
          end

          def self.prepended(base)
            base.singleton_class.prepend ClassMethods
          end

          def _new_corrector
            ::RuboCop::Cop::Corrector.new(self) if processed_source
          end

         # Class methods.
          module ClassMethods
            def v1_support?
              false
            end

            def support_autocorrect?
              method_defined?(:autocorrect)
            end
          end

          private

          def _emulate_v0_callsequence(corrector)
            lambda = _correction_lambda
            yield corrector if block_given?
            if corrector && !corrector.empty?
              raise 'Your cop should extend RuboCop::Cop::Autocorrector'
            end

            begin
              lambda.call(corrector) if lambda # rubocop:disable Style/SafeNavigation
            rescue ::Parser::ClobberingError
              # ignore
            end
          end

          def _callback_argument(_range)
            return super if self.class.v1_support?

            @v0_argument
          end

          def _apply_correction(corrector)
            return super if self.class.v1_support?

            begin
              _corrector.merge!(corrector) if corrector
            rescue ::Parser::ClobberingError
              # ignore
            end
          end

          def _correction_lambda
            return unless correction_strategy == :corrected

            _dedup_on_node(@v0_argument) do
              autocorrect(@v0_argument)
            end
          end

          def _dedup_on_node(node)
            @corrected_nodes ||= {}.compare_by_identity
            yield unless @corrected_nodes.key?(node)
          ensure
            @corrected_nodes[node] = true
          end
        end
      end
    end
  end
end
