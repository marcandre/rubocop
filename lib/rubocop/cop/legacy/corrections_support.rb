# frozen_string_literal: true

module RuboCop
  module Cop
    module Legacy
      # Legacy support for Corrector#corrections
      # See manual/cop_api_v1_changelog.md
      class CorrectionsProxy
        def initialize(corrector)
          @corrector = corrector
        end

        def <<(callable)
          suppress_clobbering do
            @corrector.transaction do
              callable.call(@corrector)
            end
          end
        end

        def empty?
          @corrector.empty?
        end

        def concat(corrections)
          if corrections.is_a?(CorrectionsProxy)
            suppress_clobbering do
              corrector.merge!(corrections.corrector)
            end
          else
            corrections.each { |correction| self << correction }
          end
        end

        protected

        attr_reader :corrector

        private

        def suppress_clobbering
          yield
        rescue ::Parser::ClobberingError # rubocop:disable Lint/SuppressedException
          # ignore Clobbering errors
        end
      end

      module CorrectionsSupport
        # Extension for Cop::Cop
        module Cop
          def corrections
            # warn 'Cop#corrections is deprecated' TODO
            return [] unless current_corrector

            CorrectionsProxy.new(current_corrector)
          end
        end

        # Extension for Cop::Corrector
        module Corrector
          # Support legacy corrections
          def initialize(source, corr = [])
            super(source)
            if corr.is_a?(CorrectionsProxy)
              merge!(corr.send(:corrector))
            else
              # warn "Corrector.new with corrections is deprecated." unless corr.empty? TODO
              corr.each do |c|
                corrections << c
              end
            end
          end

          def corrections
            # warn "#corrections is deprecated. Open an issue if you have a valid usecase." TODO
            CorrectionsProxy.new(self)
          end
        end
      end
    end
  end
end
