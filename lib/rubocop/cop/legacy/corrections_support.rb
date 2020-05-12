# frozen_string_literal: true

module RuboCop
  module Cop
    module Legacy
      # Legacy support for Corrector#corrections
      # Used to be an array of lambdas to be called on a corrector
      class CorrectionsProxy
        def initialize(corrector)
          @corrector = corrector
        end

        def <<(callable)
          @corrector.transaction do
            callable.call(@corrector)
          end
        rescue ErrorWithAnalyzedFileLocation => e
          # ignore Clobbering errors
          raise e unless e.cause.is_a?(::Parser::ClobberingError)
        end

        def empty?
          @corrector.empty?
        end

        def concat(corrections)
          corrections.each { |correction| self << correction }
        end

        protected

        attr_reader :corrector
      end

      module CorrectionsSupport
        # Support legacy corrections
        def initialize(source_buffer, corr = [])
          super(source_buffer)

          # warn "Corrector.new with corrections is deprecated." unless corr.empty?
          corr.each do |c|
            corrections << c
          end
        end

        def corrections
          # warn "Corrector#corrections is deprecated. Open an issue if you have a valid usecase."
          CorrectionsProxy.new(self)
        end
      end
    end
  end
end
