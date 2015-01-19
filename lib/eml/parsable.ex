defprotocol Eml.Parsable do
  @moduledoc """
  The Eml Parsable protocol.

  This protocol is used by `Eml.parse/2` function to
  parse and convert different Elixir data types.
  """

  def parse(data, lang)
end

defimpl Eml.Parsable, for: BitString do
  def parse(data, lang), do: lang.parse(data, BitString)
end

defimpl Eml.Parsable, for: Integer do
  def parse(data, lang), do: lang.parse(data, Integer)
end

defimpl Eml.Parsable, for: Float do
  def parse(data, lang), do: lang.parse(data, Float)
end

defimpl Eml.Parsable, for: Tuple do
  def parse(data, lang), do: lang.parse(data, Tuple)
end

defimpl Eml.Parsable, for: Atom do
  def parse(nil, _lang),   do: nil
  def parse(true, lang),   do: lang.parse(true, Atom)
  def parse(false, lang),  do: lang.parse(false, Atom)
  def parse(param, _lang), do: %Eml.Parameter{id: param}
end

defimpl Eml.Parsable, for: [Eml.Element, Eml.Parameter, Eml.Template] do
  def parse(data, _lang), do: data
end

defimpl Eml.Parsable, for: [Function, PID, Port, Reference, List, Map] do
  def parse(data, _lang), do: { :error, "Unparsable data: #{inspect data}" }
end
