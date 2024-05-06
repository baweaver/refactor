# frozen_string_literal: true

RSpec.describe Refactor do
  let(:shorthand_rule) do
    Class.new(Refactor::Rule) do
      def on_block(node)
        return unless node in [:block, receiver,
          [[:arg, arg_name]], [:send, [:lvar, ^arg_name], method_name]
        ]

        replace(node, "#{receiver.source}(&:#{method_name})")
      end
    end
  end

  let(:big_decimal_rule) do
    Class.new(Refactor::Rule) do
      def on_send(node)
        return unless node in [:send, _, :BigDecimal,
          [:float | :int, value]
        ]

        replace(node, "BigDecimal('#{value}')")
      end
    end
  end

  let(:hash_ref_default_rule) do
    Class.new(Refactor::Rule) do
      def on_send(node)
        return unless node in [:send, [:const, nil, :Hash], :new,
          [:array | :hash] => reference_value
        ]

        replace(node, "Hash.new { |h, k| h[k] = #{reference_value.source} }")
      end
    end
  end

  it "has a version number" do
    expect(Refactor::VERSION).not_to be nil
  end

  describe Refactor::Util do
    describe ".processed_source_from" do
      it 'can process the source of Ruby code' do
        result = described_class.processed_source_from('1 + 2')

        expect(result).to be_a(RuboCop::AST::ProcessedSource)
        expect(result.raw_source).to eq('1 + 2')
      end
    end

    describe ".ast_from" do
      it 'can derive an AST from Ruby code' do
        result = described_class.ast_from('1 + 2')

        expect(result).to be_a(RuboCop::AST::Node)
        expect(result.source).to eq('1 + 2')
      end
    end

    describe ".deep_deconstruct" do
      it 'can represent an ASTs pattern match structure from Ruby code' do
        result = described_class.deep_deconstruct(
          described_class.ast_from('1 + 2')
        )

        expect(result).to be_a(Array)
        expect(result).to eq([:send, [:int, 1], :+, [:int, 2]])
      end
    end

    describe ".deconstruct_ast" do
      it 'can represent an ASTs pattern match structure from Ruby code' do
        result = described_class.deconstruct_ast('1 + 2')

        expect(result).to be_a(Array)
        expect(result).to eq([:send, [:int, 1], :+, [:int, 2]])
      end
    end
  end

  describe Refactor::Rule do
    let(:target_source) { "[1, 2, 3].select { |v| v.even? }" }
    let(:corrected_source) { "[1, 2, 3].select(&:even?)" }

    it 'creates a valid rule' do
      expect(shorthand_rule.superclass).to eq(Refactor::Rule)
    end

    describe ".process" do
      it "processes a rule inline for convenience" do
        expect(shorthand_rule.process(target_source)).to eq(corrected_source)
      end
    end
  end

  describe Refactor::Rewriter do
    let(:rules) { [shorthand_rule, big_decimal_rule, hash_ref_default_rule] }
    let(:source) do
      <<~RUBY
        [1, 2, 3].select { |v| v.even? }

        value = BigDecimal(5.3)
        groups = Hash.new({})
      RUBY
    end

    subject { described_class.new(rules:) }

    it 'rewrites based on multiple rules' do
      expect(subject.process(source)).to eq <<~RUBY
        [1, 2, 3].select(&:even?)

        value = BigDecimal('5.3')
        groups = Hash.new { |h, k| h[k] = {} }
      RUBY
    end
  end
end
