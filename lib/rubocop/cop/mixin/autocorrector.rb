# frozen_string_literal: true

module RuboCop
  module Cop
    # extend this module to signal autocorrection support
    module Autocorrector
      def support_autocorrect?
        true
      end
    end
  end
end
