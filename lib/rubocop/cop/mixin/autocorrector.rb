# frozen_string_literal: true

require_relative 'v1_support'

module RuboCop
  module Cop
    # extend this module to signal compliance with V1 API and
    # that the cop supports autocorrection
    #
    module Autocorrector
      include V1Support

      def support_autocorrect?
        true
      end
    end
  end
end
