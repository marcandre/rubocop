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
        module Cop
          def corrections
            # warn 'Cop#corrections is deprecated' TODO
            @corrector.corrections
          end
        end

        module Corrector
          # Support legacy corrections
          def initialize(source, corr = [])
            super(source)

            if corr.is_a?(CorrectionsProxy)
              merge!(corr.send :corrector)
            else
              # warn "Corrector.new with corrections is deprecated." unless corr.empty? TODO
              corr.each do |c|
                corrections << c
              end
            end
          end

          def corrections
            # warn "Corrector#corrections is deprecated. Open an issue if you have a valid usecase." TODO
            CorrectionsProxy.new(self)
          end
        end
      end
    end
  end
end
