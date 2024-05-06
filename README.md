# Refactor

Utilities for refactoring and upgrading Ruby code based on ASTs.

Consider reading [ASTs in Ruby - Pattern Matching](https://dev.to/baweaver/asts-in-ruby-pattern-matching-mjd) as a primer for using this gem, as it will introduce concepts of pattern matching and ASTs in more detail.

## Original Attribution

This gem is a continuation of the work by @afeld and their Refactor gem here:

https://github.com/afeld/refactor

## Usage

Refactor works via rules, similar to RuboCop:

```ruby
# Inherits from base rule, which provides a lot of utilities
# to match and replace with.
class ShorthandRule < Refactor::Rule
  # The code we're trying to work with here is:
  #
  #    [1, 2, 3].select { |v| v.even? }
  #
  # ...and we want to make it into:
  #
  #    [1, 2, 3].select(&:even?)
  #
  def on_block(node)
    return unless node in [:block, receiver,
      [[:arg, arg_name]], [:send, [:lvar, ^arg_name], method_name]
    ]

    replace(node, "#{receiver.source}(&:#{method_name})")
  end
end

ShorthandRule.process("[1, 2, 3].select { |v| v.even? }")
# => [1, 2, 3].select(&:even?)
```

If we add multiple rules we'll want to use a `Rewriter` instead to apply all of them without the potential for collision:

```ruby
class BigDecimalRule < Refactor::Rule
  def on_send(node)
    return unless node in [:send, _, :BigDecimal,
      [:float | :int, value]
    ]

    replace(node, "BigDecimal('#{value}')")
  end
end

class HashRefDefaultRule < Refactor::Rule
  def on_send(node)
    return unless node in [:send, [:const, nil, :Hash], :new,
      [:array | :hash] => reference_value
    ]

    replace(node, "Hash.new { |h, k| h[k] = #{reference_value.source} }")
  end
end

rewriter = Refactor::Rewriter.new(rules: [ShorthandRule, BigDecimalRule, HashRefDefaultRule])
rewriter.process <<~RUBY
  [1, 2, 3].select { |v| v.even? }

  value = BigDecimal(5.3)
  groups = Hash.new({})
RUBY
# => <<~RUBY
#   [1, 2, 3].select(&:even?)
#
#   value = BigDecimal('5.3')
#   groups = Hash.new { |h, k| h[k] = {} }
# RUBY
```

## Why Not RuboCop?

In most cases you likely want to use RuboCop as it has more robust support and testing. This gem is currently more experimental and focused exclusively on refactoring and AST manipulations in a more minimal sense.

## Installation

Install the gem and add to the application's Gemfile by executing:

```
bundle add refactor
```

If bundler is not being used to manage dependencies, install the gem by executing:

```
gem install refactor
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/baweaver/refactor. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/baweaver/refactor/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Refactor project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/baweaver/refactor/blob/main/CODE_OF_CONDUCT.md).
