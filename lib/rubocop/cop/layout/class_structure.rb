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
      class ClassStructure < Base
        include VisibilityHelp
        extend AutoCorrector

        MSG = '`%<category>s` is supposed to appear before `%<previous>s`.'
        DEFAULT_CATEGORIES = %i[methods class_methods constants class_singleton initializer].freeze

        def self.support_multiple_source?
          true
        end

        def initialize(*)
          super
          @classifer = Utils::ClassChildrenClassifier.new(all_symbolized_categories)
          @expected_order_index = expected_order.map.with_index.to_h.transform_keys(&:to_sym)
        end

        # @!method dynamic_constant?(node)
        def_node_matcher :dynamic_constant?, <<~PATTERN
          (casgn nil? _ (send ...))
        PATTERN

        # Validates code style on class declaration.
        # Add offense when find a node out of expected order.
        def on_class(class_node)
          previous = -1
          classify_all(class_node).each do |node|
            next unless (index = group_order(node))

            if index < previous
              message = format(MSG, category: expected_order[index],
                                    previous: expected_order[previous])
              add_offense(node, message: message) { |corrector| autocorrect(corrector, node) }
            end
            previous = index
          end
        end

        alias on_sclass on_class

        private

        def all_symbolized_categories
          @all_symbolized_categories ||= {
            **ungrouped_categories.map { |categ| [categ, [categ]] }.to_h,
            **symbolized_categories
          }
        end

        # @return [Array<Symbol>] macros appearing directly in ExpectedOrder
        def ungrouped_categories
          @ungrouped_categories ||= expected_order
                                    .map { |str| str.sub(/^(public|protected|private)_/, '') }
                                    .uniq
                                    .map(&:to_sym) - DEFAULT_CATEGORIES
        end

        # @return [Hash<Symbol => Array<Symbol>>] config of Categories, using symbols
        def symbolized_categories
          @symbolized_categories ||= categories.map do |key, values|
            [key.to_sym, values.map(&:to_sym)]
          end.to_h
        end

        def classify_all(class_node)
          @classification = @classifer.classify_children(class_node)
          @classification.map do |node, classification|
            node if complete_classification(node, classification)
          end.compact
        end

        def complete_classification(_node, classification) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
          return unless classification

          affects = classification[:affects_categories] || []
          categ = classification[:category]
          # post macros without a particular category and
          # refering only to unknowns are ignored
          # (e.g. `private :some_unknown_method`)
          return if classification[:macro] == :post && categ.nil? && affects.empty?

          categ ||= classification[:group]
          visibility = classification[:visibility]
          classification[:group_order] = \
            if affects.empty?
              find_group_order(visibility, categ)
            else
              all = affects.map { |name| find_group_order(visibility, name) }
              classification[:macro] == :pre ? all.min : all.max
            end
        end

        def find_group_order(visibility, categ)
          visibility_categ = :"#{visibility}_#{categ}"
          @expected_order_index[visibility_categ] || @expected_order_index[categ]
        end

        # Autocorrect by swapping between two nodes autocorrecting them
        def autocorrect(corrector, node)
          return if dynamic_constant?(node)

          previous = node.left_siblings.find do |sibling|
            !ignore_for_autocorrect?(node, sibling)
          end

          # We handle empty lines as follows:
          # if `current` is preceeded with an empty line, remove it
          # and add an empty line after `current`.
          #
          # This way:
          #   <previous><current> => <current><previous>
          #   <previous>\n<current> => <current>\n<previous>
          #
          # Of course, `current` and `previous` may not be adjacent,
          # but this heuristic should provide adequate results.
          current_range = source_range_with_comment(node)
          previous_range = source_range_with_comment(previous)

          if (empty_line = preceeding_empty_line(current_range))
            corrector.remove(empty_line)
            corrector.insert_before(previous_range, "\n")
          end
          corrector.insert_before(previous_range, current_range.source)
          corrector.remove(current_range)
        end

        # @return [Range | nil]
        def preceeding_empty_line(range)
          prec = buffer.line_range(range.line - 1).adjust(end_pos: +1)
          prec if prec.source.blank?
        end

        # @return [Integer | nil]
        def group_order(node)
          return unless (c = @classification[node])

          c[:group_order]
        end

        def ignore_for_autocorrect?(node, sibling)
          index = group_order(node)
          sibling_index = group_order(sibling)

          sibling_index.nil? || index == sibling_index
        end

        def source_range_with_comment(node)
          node.loc.expression.with(
            begin_pos: begin_pos_with_comment(node),
            end_pos: end_position_for(node) + 1
          )
        end

        def end_position_for(node)
          heredoc = find_heredoc(node)
          return heredoc.location.heredoc_end.end_pos if heredoc

          end_line = buffer.line_for_position(node.loc.expression.end_pos)
          buffer.line_range(end_line).end_pos
        end

        def begin_pos_with_comment(node)
          first_comment = nil
          (node.first_line - 1).downto(1) do |annotation_line|
            break unless (comment = processed_source.comment_at_line(annotation_line))

            first_comment = comment
          end

          start_line_position(first_comment || node)
        end

        def start_line_position(node)
          buffer.line_range(node.loc.line).begin_pos
        end

        def find_heredoc(node)
          node.each_node(:str, :dstr, :xstr).find(&:heredoc?)
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
          cop_config['Categories'] || {}
        end
      end
    end
  end
end
