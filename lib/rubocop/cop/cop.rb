# frozen_string_literal: true

require 'uri'
require_relative 'legacy/corrections_proxy.rb'

module RuboCop
  module Cop
    # Legacy scaffold for Cops.
    # Use Cop::Base instead
    # See manual/cop_api_v1_changelog.md
    class Cop < Base
      # Deprecated
      Correction = Struct.new(:lambda, :node, :cop) do
        def call(corrector)
          lambda.call(corrector)
        rescue StandardError => e
          raise ErrorWithAnalyzedFileLocation.new(
            cause: e, node: node, cop: cop
          )
        end
      end

      # rubocop:disable Metrics/MethodLength
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
      # rubocop:enable Metrics/MethodLength

      def find_location(node, loc)
        warn 'deprecated' if self.class.v1_support?
        # Location can be provided as a symbol, e.g.: `:keyword`
        loc.is_a?(Symbol) ? node.loc.public_send(loc) : loc
      end

      def support_autocorrect?
        # warn 'deprecated, use cop.class.support_autocorrect?' TODO
        self.class.support_autocorrect?
      end

      def self.v1_support?
        false
      end

      def self.support_autocorrect?
        method_defined?(:autocorrect)
      end

      # Deprecated
      def corrections
        # warn 'Cop#corrections is deprecated' TODO
        return [] unless current_corrector

        Legacy::CorrectionsProxy.new(current_corrector)
      end

      ### Deprecated registry access

      # Deprecated. Use Registry.global
      def self.registry
        Registry.global
      end

      # Deprecated. Use Registry.all
      def self.all
        Registry.all
      end

      # Deprecated. Use Registry.qualified_cop_name
      def self.qualified_cop_name(name, origin)
        Registry.qualified_cop_name(name, origin)
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
        unless corrector.empty?
          raise 'Your cop must inherit from Cop::Base and extend Autocorrector'
        end

        return unless lambda

        suppress_clobbering do
          lambda.call(corrector)
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
