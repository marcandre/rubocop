# frozen_string_literal: true

module RuboCop
  module Cop
    # extend this module to signal compliance with V1 API
    #
    module V1Support
      def v1_support?
        true
      end
    end
  end
end
