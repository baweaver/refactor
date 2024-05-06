# All the stuff I've extracted for the moment until I get it working cleanly
# or for release in a later commit. For now this may be interesting for the
# sake of reading so I'll leave this in.
module Refactor
  module Util
    REPL_SOURCE = Regexp.union('(IRB)', '(pry)')

    def self.extract_block_ast(block)
      source_file, source_line = block.source_location

      # REPL defined, we gotta do some more work here

      raise ArgumentError, 'Cannot extract source from REPL' if REPL_SOURCE.match?(source_file)

      file_ast = ast_from(File.read(source_file))

      file_ast.each_node.find do |node|
        node.block_type? && node.first_line == source_line
      end
    end

    def self.pattern_deconstruct(node, tokens: [], seen: Hash.new(0), is_head: false)
      if node.respond_to?(:deconstruct)
        # Receivers especially tend to get nested like this
        if node in [:send, nil, potential_token]
          if potential_token == :_ || tokens.include?(potential_token)
            return Tokens::Literal.new(potential_token)
          end
        end

        node.deconstruct.each_with_index.map do |node, i|
          pattern_deconstruct(node, tokens:, seen:, is_head: i.zero?)
        end
      else
        return node if node.nil? || is_head || !tokens.include?(node)

        seen[node] += 1
        is_repeated = seen[node] > 1

        Tokens::Literal.new("#{'^' if is_repeated}#{node}")
      end
    end
  end

  # Any special tokens that do not cleanly introspect.
  module Tokens
    # Prevents quotes from displaying when assembling
    # code later.
    class Literal
      def initialize(string)
        @string = string
      end

      def to_s
        @string
      end

      def inspect
        @string
      end
    end
  end

  # Wrap a pattern match, potentially do other interesting things
  # later on.
  class Matcher
    def initialize(&pattern)
      @pattern = pattern
    end

    def call(value)
      @pattern.call(value)
    end

    alias === call

    def to_proc
      @pattern
    end
  end

  # Not sure this is a wise idea, but it _is_ a fun idea.
  module RuleMacros
    def matches(string = nil, &block)
      return matches_block(&block) if block_given?

      # Sort is a stupid hack to beat partial word matches. Should make this smarter
      # later on. Probably invoke this into a tree rewriter ruleset which
      # is far more involved than I want to do tonight
      tokens = string.scan(/\$\w+/).sort_by { -_1.size }
      token_match = Regexp.union(tokens)
      clean_string = string.gsub(token_match) { |v| v[1..-1] }
      input_ast = ast_from(clean_string)
      pattern_type = input_ast.type

      # Strip off the global-psuedo-var syntax
      scanned_tokens = tokens.map { _1[1..-1].to_sym }
      match_data_hash = scanned_tokens
        .map { |v| "#{v}:" }
        .then { |vs| "{ #{vs.join(', ')}, pattern_type: :#{pattern_type} }" }

      pattern_match_stanza = Util.pattern_deconstruct(input_ast, tokens: scanned_tokens)

      source = <<~RUBY
        def pattern_type
          :#{pattern_type}
        end

        def match?(value)
          ast = value.is_a?(RuboCop::AST::Node) ? value : Util.ast_from(value)

          return false unless ast in #{pattern_match_stanza}
          return false unless ast.type == :#{pattern_type}

          true
        end

        def match(value)
          ast = value.is_a?(RuboCop::AST::Node) ? value : Util.ast_from(value)

          return false unless ast in #{pattern_match_stanza}
          return false unless ast.type == :#{pattern_type}

          #{match_data_hash}
        end
      RUBY

      instance_eval(source)
    end

    def replace(string = nil, &block)
      block_ast = Util.extract_block_ast(block)

      # pp block_ast
      # pp Util.deep_deconstruct(block_ast)

      does_match = block_ast in [:block,
        [:send, nil, :replace],
        [[:arg, node_arg_name], [:arg, match_data_arg_name]],
        replacement_body
      ]

      unless does_match
        raise ArgumentError, "Block is not in correct format for matches macro: \n#{block_ast.source}"
      end

      new_method_source = <<~RUBY
        def translate(#{node_arg_name}, #{match_data_arg_name})
          #{replacement_body.source}
        end

        def match_and_replace(node)
          pp(node:)
          match_data = matches(node) or return false
          pp(match_data:)
          new_source = translate(node, match_data)
          pp(new_source:)

          @rewriter.replace(node.loc.expression, new_source)
        end
      RUBY

      puts '', "REPLACE", new_method_source, '', ''

      instance_eval(new_method_source)
    end

    private def matches_block(&block)
      block_ast = Util.extract_block_ast(block)

      does_match = block_ast in [:block,
        [:send, nil, :matches],
        [[:arg, node_arg_name]],
        [:match_pattern_p,
          [:lvar, ^node_arg_name], # Should be the same, or it'd fail anyways
          [:array_pattern, [:sym, pattern_type], *], # The rest doesn't really matter
          *
        ] => pattern_match_stanza
      ]

      unless does_match
        raise ArgumentError, "Block is not in correct format for matches macro: \n#{block_ast.source}"
      end

      # Requires descent, re-iterate
      match_variables = block_ast.each_node.select { |n| n.type == :match_var }.map(&:source)
      match_data_hash = match_variables
        .map { |v| "#{v}:" }
        .then { |vs| "{ #{vs.join(', ')}, pattern_type: :#{pattern_type} }" }

      new_method_source = <<~RUBY
        def pattern_type
          :#{pattern_type}
        end

        def on_#{pattern_type}(node)
          pp(on_#{pattern_type}: true, node:, pattern_type:)
          match_and_replace(node)
        end

        def match_and_replace(node)
          return # Fake version until a replacement happens and overwrites this later
        end

        def match?(#{node_arg_name})
          return false unless #{node_arg_name}.type == :#{pattern_type}
          return false unless #{pattern_match_stanza.source}

          true
        end

        def match(#{node_arg_name})
          return false unless #{node_arg_name}.type == :#{pattern_type}
          return false unless #{pattern_match_stanza.source}

          #{match_data_hash}
        end
      RUBY

      puts '', "MATCH", new_method_source, '', ''

      instance_eval(new_method_source)
    end

    private def create_translation_function(input_string:, target_string:)
      # Sort is a stupid hack to beat partial word matches. Should make this smarter
      # later on. Probably invoke this into a tree rewriter ruleset which
      # is far more involved than I want to do tonight
      input_tokens = input_string.scan(/\$\w+/).sort_by { -_1.size }
      input_token_match = Regexp.union(input_tokens)
      input_clean = input_string.gsub(input_token_match) { |v| v[1..-1] }
      input_ast = ast_from(input_clean)

      # Strip off the global-psuedo-var syntax
      input_scan_tokens = input_tokens.map { _1[1..-1].to_sym }

      pattern_match_stanza = pattern_deconstruct(input_ast, tokens: input_scan_tokens)

      # Interpolate the new values
      #
      # Don't mind the really danged hacky AST to source coercion here,
      # need to think on cleaning that up real fast later.
      target_source = target_string.gsub(input_token_match) do |v|
        "\#\{#{v[1..-1]}.then { |x| x.is_a?(RuboCop::AST::Node) ? x.source : x }\}"
      end

      extractor_source = <<~RUBY
        -> node do
          node = node.is_a?(String) ? ast_from(node) : node
          return unless node in #{pattern_match_stanza}

          "#{target_source}"
        end
      RUBY

      puts extractor_source

      eval(extractor_source)
    end
  end
end

# Tests for RuleMacros for later
# context 'When using RuleMacros' do
#   let(:macro_rule) do
#     Class.new(Refactor::Rule) do
#       matches do |macro_node|
#         macro_node in [:block, receiver,
#           [[:arg, arg_name]], [:send, [:lvar, ^arg_name], method_name]
#         ]
#       end

#       replace do |_macro_node, match_data|
#         "#{match_data[:receiver].source}(&:#{match_data[:method_name]})"
#       end
#     end
#   end

#   it 'creates a valid rule' do
#     expect(macro_rule.superclass).to eq(Refactor::Rule)
#   end

#   describe ".process" do
#     it "processes a rule inline for convenience" do
#       expect(macro_rule.process(target_source)).to eq(corrected_source)
#     end
#   end
# end
