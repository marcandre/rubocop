# frozen_string_literal: true

require 'uri'
require_relative 'legacy/corrections_proxy.rb'

module RuboCop
  module Cop
    # Legacy scaffold for Cops.
    # Use Cop::Base instead
    # See https://docs.rubocop.org/rubocop/cop_api_v1_changelog.html
    class Cop < Base
      attr_reader :offenses

      exclude_from_registry

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

      def add_offense(node_or_range, location: :expression, message: nil, severity: nil, &block)
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

      def find_location(node, loc)
        # Location can be provided as a symbol, e.g.: `:keyword`
        loc.is_a?(Symbol) ? node.loc.public_send(loc) : loc
      end

      def support_autocorrect?
        # warn 'deprecated, use cop.class.support_autocorrect?' TODO
        self.class.support_autocorrect?
      end

      def self.support_autocorrect?
        method_defined?(:autocorrect)
      end

      # Deprecated
      def corrections
        # warn 'Cop#corrections is deprecated' TODO
        return [] unless @last_corrector

        Legacy::CorrectionsProxy.new(@last_corrector)
      end

      # Called before all on_... have been called
      def on_walk_begin
        investigate(processed_source) if respond_to?(:investigate)
      end

      # Called after all on_... have been called
      def on_walk_end
        investigate_post_walk(processed_source) if respond_to?(:investigate_post_walk)
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

      def begin_investigation(processed_source)
        super
        @offenses = @current_offenses
        @last_corrector = @current_corrector
      end

      # Override Base
      def callback_argument(_range)
        @v0_argument
      end

      def apply_correction(corrector)
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
        return unless correction_strategy == :attempt_correction && support_autocorrect?

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
      rescue ::Parser::ClobberingError
        # ignore Clobbering errors
      end
    end
  end
end
