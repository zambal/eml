defprotocol Eml.Readable do
  @moduledoc """
  The Eml Readable protocol.
  """

  def read(data, lang)
end

defimpl Eml.Readable, for: BitString do
  def read(data, lang), do: lang.read(data, BitString)
end

defimpl Eml.Readable, for: Integer do
  def read(data, lang), do: lang.read(data, Integer)
end

defimpl Eml.Readable, for: Float do
  def read(data, lang), do: lang.read(data, Float)
end

defimpl Eml.Readable, for: Tuple do
  def read(data, lang), do: lang.read(data, Tuple)
end

defimpl Eml.Readable, for: Atom do
  def read(nil, _lang),   do: nil
  def read(true, lang),   do: lang.read(true, Atom)
  def read(false, lang),  do: lang.read(false, Atom)
  def read(param, _lang), do: Eml.Parameter.new(param)
end

defimpl Eml.Readable, for: [Eml.Markup, Eml.Parameter, Eml.Template] do
  def read(data, _lang), do: data
end

defimpl Eml.Readable, for: [Function, PID, Port, Reference, List] do
  def read(data, _lang), do: { :error, "Unreadable data: #{inspect data}" }
end
