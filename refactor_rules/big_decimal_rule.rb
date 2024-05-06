
class BigDecimalRule < Refactor::Rule
  def on_send(node)
    return unless node in [:send, _, :BigDecimal,
      [:float | :int, value]
    ]

    replace(node, "BigDecimal('#{value}')")
  end
end
