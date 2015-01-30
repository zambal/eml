defmodule Eml.CompileError do
  defexception [:type, :value]

  def message(exception) do
    "type: #{exception.type}, value: #{inspect exception.value}"
  end
end

defmodule Eml.ParseError do
  defexception [:type, :value]

  def message(exception) do
    "type: #{exception.type}, value: #{inspect exception.value}"
  end
end
