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
