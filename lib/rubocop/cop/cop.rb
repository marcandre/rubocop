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

      # Global Registry
      @registry = Registry.new

      class << self
        attr_reader :registry
      end

      def self.all
        registry.without_department(:Test).cops
      end

      def self.qualified_cop_name(name, origin)
        registry.qualified_cop_name(name, origin)
      end

    end

    def Base.inherited(subclass)
      Cop.registry.enlist(subclass)
    end
  end
end
