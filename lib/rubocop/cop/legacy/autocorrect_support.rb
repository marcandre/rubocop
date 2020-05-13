# frozen_string_literal: true

module RuboCop
  module Cop
    module Legacy
      # Legacy support for Cop#autocorrect

      module AutocorrectSupport

        Correction = Struct.new(:lambda, :node, :cop) do
          def call(corrector)
            lambda.call(corrector)
          rescue StandardError => e
            raise ErrorWithAnalyzedFileLocation.new(
              cause: e, node: node, cop: cop
            )
          end
        end

        ### add_offense arguments
        # Legacy: interface allowed for a `node`, with an optional `location` (symbol or range)
        # or a range with a mandatory range as the location.
        # Current: pass range (or node as a shortcut for node.loc.expression), no `location`
        #
        ### de-dupping changes
        # Both de-duppe on `range`: won't process the duplicated offenses at all
        # Legacy: if offense on same `node` but different `range`: multiple offenses but single auto-correct call
        # Current: not applicable
        #
        ### `#autocorrect`
        # Legacy: calls `autocorrect` unless it is disabled / autocorrect is off
        # Current: yields a corrector unless it is disabled. No support for `autocorrect`
        #
        ### yield
        # Both yield under the same conditions (unless cop is disabled for that line), but:
        # Legacy: yields after offense added to `#offenses`
        # Current: yields before offense is added to `#offenses`.
        #
        def add_offense(node_or_range, location: :expression, message: nil, severity: nil)
          if _legacy_support?
            @legacy_argument = node_or_range
            range = find_location(node_or_range, location)
            super(range, message: message, severity: severity) do |corrector|
              lambda = if correction_strategy(range) == :corrected
                _dedup_on_node(node_or_range) do
                  autocorrect(node_or_range)
                end
              end
              yield corrector if block_given?
              warn 'Your cop should include RuboCop::Cop::Autocorrector' unless corrector.empty?
              lambda.call(corrector) if lambda
            end
          else
            raise 'Parameter location is not supported with the new API;' \
                  'pass the node or range as first argument' unless location == :expression
            super(node_or_range, message: message, severity: severity)
          end
        end

        def find_location(node, loc)
          warn 'deprecated' unless _legacy_support?
          # Location can be provided as a symbol, e.g.: `:keyword`
          loc.is_a?(Symbol) ? node.loc.public_send(loc) : loc
        end

        private

        def _legacy_support?
          true
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
