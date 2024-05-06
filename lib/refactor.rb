# frozen_string_literal: true

require_relative 'refactor/version'

# Eventually we may consider dropping RuboCop and working more directly
# on top of Parser itself
require 'rubocop'

module Refactor
  # Utilities for working with ASTs
  module Util
    def self.deconstruct_ast(string)
      deep_deconstruct(ast_from(string))
    end

    # Makes it easier to break down an AST into what we'd like to match against
    # eventually.
    def self.deep_deconstruct(node)
      return node unless node.respond_to?(:deconstruct)

      node.deconstruct.map { deep_deconstruct(_1) }
    end

    # Convert a string into its AST representation
    def self.ast_from(string)
      processed_source_from(string).ast
    end

    def self.processed_source_from(string)
      RuboCop::ProcessedSource.new(string, RUBY_VERSION.to_f)
    end
  end

  # Wrapper for rule processors to simplify the code
  # needed to run one.
  class Rule < Parser::AST::Processor
    include RuboCop::AST::Traversal

    protected attr_reader :rewriter

    def initialize(rewriter)
      @rewriter = rewriter
      super()
    end

    def self.process(string)
      Rewriter.new(rules: [self]).process(string)
    end

    def process_regular_node(node)
      return matches(node) if defined?(matches)

      super()
    end

    protected def replace(node, new_code)
      rewriter.replace(node.loc.expression, new_code)
    end
  end

  # Full rewriter, typically used for processing multiple rules
  class Rewriter
    def initialize(rules: [])
      @rules = rules
    end

    def process(string)
      # No sense in processing anything if there's nothing to apply it to
      return string if @rules.empty?

      source = Util.processed_source_from(string)
      ast = source.ast

      source_buffer = source.buffer

      rewriter = Parser::Source::TreeRewriter.new(source_buffer)

      @rules.each do |rule_class|
        rule = rule_class.new(rewriter)
        ast.each_node { |node| rule.process(node) }
      end

      rewriter.process
    end
  end
end
