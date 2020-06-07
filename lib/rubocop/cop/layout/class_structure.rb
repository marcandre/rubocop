# frozen_string_literal: true

module RuboCop
  module Cop
    module Layout
      # Checks if the code style follows the ExpectedOrder configuration:
      #
      # `Categories` allows us to map macro names into a category.
      #
      # Consider an example of code style that covers the following order:
      #
      # * Module inclusion (include, prepend, extend)
      # * Constants
      # * Associations (has_one, has_many)
      # * Public attribute macros (attr_accessor, attr_writer, attr_reader)
      # * Other macros (validates, validate)
      # * Public class methods
      # * Initializer
      # * Public instance methods
      # * Protected attribute macros (attr_accessor, attr_writer, attr_reader)
      # * Protected instance methods
      # * Private attribute macros (attr_accessor, attr_writer, attr_reader)
      # * Private instance methods
      #
      # You can configure the following order:
      #
      # [source,yaml]
      # ----
      #  Layout/ClassStructure:
      #    ExpectedOrder:
      #      - module_inclusion
      #      - constants
      #      - association
      #      - public_attribute_macros
      #      - public_delegate
      #      - macros
      #      - public_class_methods
      #      - initializer
      #      - public_methods
      #      - protected_attribute_macros
      #      - protected_methods
      #      - private_attribute_macros
      #      - private_delegate
      #      - private_methods
      # ----
      #
      # Instead of putting all literals in the expected order, is also
      # possible to group categories of macros. Visibility levels are handled
      # automatically.
      #
      # [source,yaml]
      # ----
      #  Layout/ClassStructure:
      #    Categories:
      #      association:
      #        - has_many
      #        - has_one
      #      attribute_macros:
      #        - attr_accessor
      #        - attr_reader
      #        - attr_writer
      #      macros:
      #        - validates
      #        - validate
      #      module_inclusion:
      #        - include
      #        - prepend
      #        - extend
      # ----
      #
      # @example
      #   # bad
      #   # Expect extend be before constant
      #   class Person < ApplicationRecord
      #     has_many :orders
      #     ANSWER = 42
      #
      #     extend SomeModule
      #     include AnotherModule
      #   end
      #
      #   # good
      #   class Person
      #     # extend and include go first
      #     extend SomeModule
      #     include AnotherModule
      #
      #     # inner classes
      #     CustomError = Class.new(StandardError)
      #
      #     # constants are next
      #     SOME_CONSTANT = 20
      #
      #     # afterwards we have public attribute macros
      #     attr_reader :name
      #
      #     # followed by other macros (if any)
      #     validates :name
      #
      #     # then we have public delegate macros
      #     delegate :to_s, to: :name
      #
      #     # public class methods are next in line
      #     def self.some_method
      #     end
      #
      #     # initialization goes between class methods and instance methods
      #     def initialize
      #     end
      #
      #     # followed by other public instance methods
      #     def some_method
      #     end
      #
      #     # protected attribute macros and methods go next
      #     protected
      #
      #     attr_reader :protected_name
      #
      #     def some_protected_method
      #     end
      #
      #     # private attribute macros, delegate macros and methods
      #     # are grouped near the end
      #     private
      #
      #     attr_reader :private_name
      #
      #     delegate :some_private_delegate, to: :name
      #
      #     def some_private_method
      #     end
      #   end
      #
      # @see https://rubystyle.guide#consistent-classes
      class ClassStructure < Cop
        HUMANIZED_NODE_TYPE = {
          casgn: :constants,
          defs: :class_methods,
          def: :public_methods,
          sclass: :class_singleton
        }.freeze

        VISIBILITY_SCOPES = FastArray %i[private protected public]
        MSG = '`%<category>s` is supposed to appear before ' \
              '`%<previous>s`.'

        def_node_matcher :visibility_block?, <<~PATTERN
          (send nil? { :private :protected :public })
        PATTERN

        # Validates code style on class declaration.
        # Add offense when find a node out of expected order.
        def on_class(class_node)
          previous = -1
          walk_over_nested_class_definition(class_node) do |node, category|
            index = expected_order.index(category)
            if index < previous
              message = format(MSG, category: category,
                                    previous: expected_order[previous])
              add_offense(node, message: message)
            end
            previous = index
          end
        end

        # Autocorrect by swapping between two nodes autocorrecting them
        def autocorrect(node)
          node_classification = classify(node)
          previous = left_siblings_of(node).find do |sibling|
            classification = classify(sibling)
            !ignore?(classification) && node_classification != classification
          end

          current_range = source_range_with_comment(node)
          previous_range = source_range_with_comment(previous)

          lambda do |corrector|
            corrector.insert_before(previous_range, current_range.source)
            corrector.remove(current_range)
          end
        end

        private

        # Classifies a node to match with something in the {expected_order}
        # @param node to be analysed
        # @return String when the node type is a `:block` then
        #   {classify} recursively with the first children
        # @return String when the node type is a `:send` then {find_category}
        #   by method name
        # @return String otherwise trying to {humanize_node} of the current node
        def classify(node)
          return node.to_s unless node.respond_to?(:type)

          case node.type
          when :block
            classify(node.send_node)
          when :send
            find_category(node)
          else
            humanize_node(node)
          end.to_s
        end

        # Categorize a node according to the {expected_order}
        # Try to match {categories} values against the node's method_name given
        # also its visibility.
        # @param node to be analysed.
        # @return [String] with the key category or the `method_name` as string
        def find_category(node)
          name = node.method_name.to_s
          category, = categories.find { |_, names| names.include?(name) }
          key = category || name
          visibility_key = "#{node_visibility(node)}_#{key}"
          expected_order.include?(visibility_key) ? visibility_key : key
        end

        def walk_over_nested_class_definition(class_node)
          class_elements(class_node).each do |node|
            classification = classify(node)
            next if ignore?(classification)

            yield node, classification
          end
        end

        def class_elements(class_node)
          class_def = class_node.body

          return [] unless class_def

          if class_def.def_type? || class_def.send_type?
            [class_def]
          else
            class_def.children.compact
          end
        end

        def ignore?(classification)
          classification.nil? ||
            classification.to_s.end_with?('=') ||
            expected_order.index(classification).nil?
        end

        def node_visibility(node)
          scope = find_visibility_start(node)
          scope&.method_name || :public
        end

        def find_visibility_start(node)
          left_siblings_of(node)
            .reverse
            .find(&method(:visibility_block?))
        end

        # Navigate to find the last protected method
        def find_visibility_end(node)
          possible_visibilities = VISIBILITY_SCOPES - [node_visibility(node)]
          right = right_siblings_of(node)
          right.find do |child_node|
            possible_visibilities.include?(node_visibility(child_node))
          end || right.last
        end

        def siblings_of(node)
          node.parent.children
        end

        def right_siblings_of(node)
          siblings_of(node)[node.sibling_index..-1]
        end

        def left_siblings_of(node)
          siblings_of(node)[0, node.sibling_index]
        end

        def humanize_node(node)
          if node.def_type?
            return :initializer if node.method?(:initialize)

            return "#{node_visibility(node)}_methods"
          end
          HUMANIZED_NODE_TYPE[node.type] || node.type
        end

        def source_range_with_comment(node)
          begin_pos, end_pos =
            if node.def_type?
              start_node = find_visibility_start(node) || node
              end_node = find_visibility_end(node) || node
              [begin_pos_with_comment(start_node),
               end_position_for(end_node) + 1]
            else
              [begin_pos_with_comment(node), end_position_for(node)]
            end

          Parser::Source::Range.new(buffer, begin_pos, end_pos)
        end

        def end_position_for(node)
          end_line = buffer.line_for_position(node.loc.expression.end_pos)
          buffer.line_range(end_line).end_pos
        end

        def begin_pos_with_comment(node)
          annotation_line = node.first_line - 1
          first_comment = nil

          processed_source.comments_before_line(annotation_line)
                          .reverse_each do |comment|
            if comment.location.line == annotation_line
              first_comment = comment
              annotation_line -= 1
            end
          end

          start_line_position(first_comment || node)
        end

        def start_line_position(node)
          buffer.line_range(node.loc.line).begin_pos - 1
        end

        def buffer
          processed_source.buffer
        end

        # Load expected order from `ExpectedOrder` config.
        # Define new terms in the expected order by adding new {categories}.
        def expected_order
          cop_config['ExpectedOrder']
        end

        # Setting categories hash allow you to group methods in group to match
        # in the {expected_order}.
        def categories
          cop_config['Categories']
        end
      end
    end
  end
end
