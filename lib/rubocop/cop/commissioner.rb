# frozen_string_literal: true

module RuboCop
  module Cop
    # Commissioner class is responsible for processing the AST and delegating
    # work to the specified cops.
    class Commissioner
      include RuboCop::AST::Traversal

      attr_reader :errors

      def initialize(cops, forces = [], options = {})
        @cops = cops
        @forces = forces
        @options = options
        @callbacks = {}

        reset_errors
      end

      # Create methods like :on_send, :on_super, etc. They will be called
      # during AST traversal and try to call corresponding methods on cops.
      # A call to `super` is used
      # to continue iterating over the children of a node.
      # However, if we know that a certain node type (like `int`) never has
      # child nodes, there is no reason to pay the cost of calling `super`.
      Parser::Meta::NODE_TYPES.each do |node_type|
        method_name = :"on_#{node_type}"
        next unless method_defined?(method_name)

        define_method(method_name) do |node|
          trigger_responding_cops(method_name, node)
          super(node) unless NO_CHILD_NODES.include?(node_type)
        end
      end

      # @return [offenses, correctors]
      def investigate(processed_source)
        reset_errors
        reset_callbacks

        @cops.each { |cop| cop.send :begin_investigation, processed_source }
        if processed_source.valid_syntax?
          invoke(:on_walk_begin, @cops)
          invoke(:investigate, @forces, processed_source)
          walk(processed_source.ast)
          invoke(:on_walk_end, @cops)
        else
          invoke(:on_other_file, @cops)
        end
        collate_reports(@cops.map { |cop| cop.send(:complete_investigation) })
      end

      private

      def collate_reports(reports)
        reports.map(&:to_a).transpose
      end

      def trigger_responding_cops(callback, node)
        @callbacks[callback] ||= @cops.select do |cop|
          cop.respond_to?(callback)
        end
        @callbacks[callback].each do |cop|
          with_cop_error_handling(cop, node) do
            cop.send(callback, node)
          end
        end
      end

      def reset_errors
        @errors = []
      end

      def reset_callbacks
        @callbacks.clear
      end

      def invoke(callback, cops, *args)
        cops.each do |cop|
          with_cop_error_handling(cop) do
            cop.send(callback, *args)
          end
        end
      end

      # Allow blind rescues here, since we're absorbing and packaging or
      # re-raising exceptions that can be raised from within the individual
      # cops' `#investigate` methods.
      def with_cop_error_handling(cop, node = nil)
        yield
      rescue StandardError => e
        raise e if @options[:raise_error]

        err = ErrorWithAnalyzedFileLocation.new(cause: e, node: node, cop: cop)
        @errors << err
      end
    end
  end
end
