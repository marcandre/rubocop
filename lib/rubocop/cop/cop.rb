# frozen_string_literal: true

require 'uri'
require_relative 'legacy/autocorrect_support'
require_relative 'legacy/corrections_support'

module RuboCop
  module Cop
    # Legacy scaffold for Cops.
    # Use Cop::Base instead
    class Cop < Base
      include Legacy::AutocorrectSupport::Cop
      include Legacy::CorrectionsSupport::Cop

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
    end
  end
end
