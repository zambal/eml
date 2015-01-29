defprotocol Eml.Data do
  @moduledoc """
  The Eml Data protocol.

  This protocol is used by `Eml.parse/2` function to
  convert different Elixir data types to Eml content.
  """
  @spec to_eml(Eml.Data.t) :: Eml.t
  def to_eml(data)
end

defimpl Eml.Data, for: Integer do
  def to_eml(data), do: Integer.to_string(data)
end

defimpl Eml.Data, for: Float do
  def to_eml(data), do: Float.to_string(data)
end

defimpl Eml.Data, for: Atom do
  def to_eml(nil),   do: nil
  def to_eml(true),  do: "true"
  def to_eml(false), do: "false"
  def to_eml(param), do: %Eml.Parameter{id: param}
end

defimpl Eml.Data, for: [BitString, Eml.Element, Eml.Parameter, Eml.Template] do
  def to_eml(data), do: data
end
