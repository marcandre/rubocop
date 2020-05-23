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
            source = fix_source(source)
            super
          end

          private

          def fix_source(source)
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
                  emulate_v0_callsequence(corrector, &block)
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

          def self.included(base)
            base.extend ClassMethods
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

          # Override Base
          def callback_argument(_range)
            return super if self.class.v1_support?

            @v0_argument
          end

          def apply_correction(corrector)
            return super if self.class.v1_support?

            suppress_clobbering { super }
          end

          # Just for legacy
          def emulate_v0_callsequence(corrector)
            lambda = correction_lambda
            yield corrector if block_given?
            if corrector && !corrector.empty?
              raise 'Your cop must call `self.support_autocorrect = true`'
            end

            if lambda
              suppress_clobbering do
                lambda.call(corrector)
              end
            end
          end

          def correction_lambda
            return unless correction_strategy == :corrected

            dedup_on_node(@v0_argument) do
              autocorrect(@v0_argument)
            end
          end

          def dedup_on_node(node)
            @corrected_nodes ||= {}.compare_by_identity
            yield unless @corrected_nodes.key?(node)
          ensure
            @corrected_nodes[node] = true
          end

          def suppress_clobbering
            yield
          rescue ::Parser::ClobberingError # rubocop:disable Lint/SuppressedException
            # ignore Clobbering errors
          end
        end
      end
    end
  end
end
