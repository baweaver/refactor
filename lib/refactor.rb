# frozen_string_literal: true

require_relative 'refactor/version'

# Eventually we may consider dropping RuboCop and working more directly
# on top of Parser itself
require 'rubocop'

# Niceties for console output
require 'colorized_string'

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

    # def process(node)
    #   super(node).tap do |n_val|

    #   end
    # end

    # Get all actively loaded rules
    def self.descendants
      ObjectSpace.each_object(Class).select { |klass| klass < self }
    end

    def self.process(string)
      Rewriter.new(rules: [self]).process(string)
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

    # Only processes the string
    def process(string)
      load_rewriter(string).process
    end

    # Processes the string and returns a set of nested actions that
    # were taken against it.
    def process_with_context(string)
      rewriter = load_rewriter(string)

      {
        processed_source: rewriter.process,
        replacements: rewriter.as_replacements
      }
    end

    private def load_rewriter(string)
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

      rewriter
    end
  end

  # Runner for applying refactoring rules
  class Runner
    DEFAULT_RULE_DIRECTORY = 'refactor_rules'
    DEFAULT_TARGET_BLOB = '**/*.rb'

    def initialize(
      rules: [],
      rule_directory: DEFAULT_RULE_DIRECTORY,
      target_glob: DEFAULT_TARGET_BLOB,
      dry_run: false
    )
      @rule_directory = rule_directory

      if Dir.exist?(rule_directory)
        Dir["#{rule_directory}/**/*.rb"].each do |rule|
          load(rule)
        end
      else
        warn "Rules directory '#{rule_directory}' does not exist. Skipping load."
      end

      @rules = (rules + Rule.descendants).uniq

      @target_glob = target_glob
      @target_files = Dir[@target_glob]

      @rewriter = Rewriter.new(rules: @rules)
      @dry_run = dry_run
    end

    def run!(dry_run: @dry_run)
      @target_files.each do |file|
        content = File.read(file)
        @rewriter.process_with_context(content) => processed_source:, replacements:

        next if replacements.empty?

        puts "Changes made to #{file}:"

        replacements.each do |range, replacement|
          puts diff_output(range:, replacement:, file:), ''
        end

        File.write(file, processed_source) unless dry_run
      end
    end

    private def diff_output(range:, replacement:, file:, indent: 2)
      line_no = formatted_line_no(range)
      space = ' ' * indent
      large_space = ' ' * (indent + 2)

      removed_source = range
        .source
        .lines
        .map { ColorizedString["#{large_space}- #{_1}"].colorize(:red) }
        .join("\n")

      added_source = replacement
        .lines
        .map { ColorizedString["#{large_space}+ #{_1}"].colorize(:green) }
        .join("\n")

      <<~OUTPUT
        #{space}[#{file}:#{line_no}]

        #{removed_source}
        #{added_source}
      OUTPUT
    end

    private def formatted_line_no(range)
      if range.single_line?
        "L#{range.first_line}"
      else
        "L#{range.first_line}-#{range.last_line}"
      end
    end
  end
end
