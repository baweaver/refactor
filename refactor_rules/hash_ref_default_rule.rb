class HashRefDefaultRule < Refactor::Rule
  def on_send(node)
    return unless node in [:send, [:const, nil, :Hash], :new,
      [:array | :hash] => reference_value
    ]

    replace(node, "Hash.new { |h, k| h[k] = #{reference_value.source} }")
  end
end
