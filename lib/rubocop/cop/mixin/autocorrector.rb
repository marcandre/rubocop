# frozen_string_literal: true

module RuboCop
  module Cop
    # Minimalist implementation for API.
    # *** Actualy implementation would look nothing like this ***
    module Autocorrector
      Sugar = Struct.new(:do_yield) do
        def enabled?
          yield if do_yield
        end
      end

      class FakeCorrector
        attr_reader :called

        def remove(*)
          @called = true
        end

        %i[insert_before insert_after wrap replace remove_preceding
           remove_leading remove_trailing].each do |method|
          alias_method method, :remove
        end
      end

      attr_reader :block

      def add_offense(node_or_range, message: nil, severity: nil, &block)
        range = node_or_range.respond_to?(:loc) ? node_or_range.loc.expression : node_or_range
        @block = block
        if block && block.arity == 0
          raise 'This block is should accept a `corrector` argument. '\
                'If you meant to pass a post processing block, use ' \
                '`add_offense(...).enabled? { <your block here }` instead.'
        end
        super(node_or_range, location: range, message: message, severity: severity, &nil)
        Sugar.new(@offenses.last.status != :disabled)
      end

      def autocorrect(_)
        return unless @block

        corrector = FakeCorrector.new
        @block.call(corrector)
        @block if corrector.called
      end
    end
  end
end
