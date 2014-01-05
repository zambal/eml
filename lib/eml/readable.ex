defprotocol Eml.Readable do
  @moduledoc """
  The Eml Readable protocol.
  """

  def read(data, dialect)
end

defimpl Eml.Readable, for: BitString do
  def read(data, dialect), do: dialect.read(data, BitString)
end

defimpl Eml.Readable, for: Integer do
  def read(data, dialect), do: dialect.read(data, Integer)
end

defimpl Eml.Readable, for: Float do
  def read(data, dialect), do: dialect.read(data, Float)
end

defimpl Eml.Readable, for: Tuple do
  def read(data, dialect), do: dialect.read(data, Tuple)
end

defimpl Eml.Readable, for: Atom do
  def read(nil, _dialect),   do: nil
  def read(true, dialect),   do: dialect.read(true, Atom)
  def read(false, dialect),  do: dialect.read(false, Atom)
  def read(param, _dialect), do: Eml.Parameter.new(param)
end

defimpl Eml.Readable, for: [Eml.Markup, Eml.Parameter, Eml.Template] do
  def read(data, _dialect), do: data
end

defimpl Eml.Readable, for: [Function, PID, Port, Reference, List] do
  def read(data, _dialect), do: { :error, "Unreadable data: #{inspect data}" }
end
