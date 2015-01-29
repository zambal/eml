defprotocol Eml.Content do
  @moduledoc """
  The Eml Content protocol.

  This protocol is used by `Eml.parse/2` function to
  convert different Elixir data types to Eml content.
  """

  def to_eml(data)
end

defimpl Eml.Content, for: Integer do
  def to_eml(data), do: Integer.to_string(data)
end

defimpl Eml.Content, for: Float do
  def to_eml(data), do: Float.to_string(data)
end

defimpl Eml.Content, for: Atom do
  def to_eml(nil),   do: nil
  def to_eml(true),  do: "true"
  def to_eml(false), do: "false"
  def to_eml(param), do: %Eml.Parameter{id: param}
end

defimpl Eml.Content, for: [BitString, Eml.Element, Eml.Parameter, Eml.Template] do
  def to_eml(data), do: data
end
