# frozen_string_literal: true

module RuboCop
  module Cop
    # Allows easy caching of data for Cops
    module Cache
      CACHE = '@cache'

      # @api private
      Builder = Struct.new(:names) do # rubocop:disable Metrics/BlockLength
        def camelize(str)
          str.split('_').map(&:capitalize).join
        end

        def module_name
          suffix = camelize(names.map(&:to_s).join('_and_'))
          "#{suffix}Cache"
        end

        def add_cache_invalidation(mod)
          mod.module_eval <<~RUBY, __FILE__, __LINE__ + 1
            def on_walk_begin
              #{CACHE} = {}
              super
            end
          RUBY
        end

        def add_accessor(mod, method)
          mod.module_eval <<~RUBY, __FILE__, __LINE__ + 1
            def #{method}
              #{CACHE} ||= {}
              #{CACHE}.fetch(:#{method}) do
                #{CACHE}[:#{method}] = super
              end
            end
          RUBY
        end

        def create_module
          Module.new.tap do |mod|
            add_cache_invalidation(mod)
            names.each do |method|
              add_accessor(mod, method)
            end
          end
        end

        def inject(base)
          mod = create_module
          base.const_set(module_name, mod)
          base.prepend(mod)
        end
      end

      # Caches the given methods and clears it in method `on_walk_begin`
      def cache(*names)
        Builder.new(names).inject(self)
      end
    end
  end
end
