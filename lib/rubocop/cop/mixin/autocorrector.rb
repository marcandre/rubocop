# frozen_string_literal: true

module RuboCop
  module Cop
    # This module allows a more streamlined way to add an offense
    # and make a correction at once.
    #
    module Autocorrector
      def support_autocorrect?
        true
      end

      private

      def _legacy_support?
        false
      end
    end
  end
end
