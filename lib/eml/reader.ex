defprotocol Eml.Readable do
  @moduledoc """
  The Eml Readable protocol.
  """

  def read(data, reader)
end

defmodule Eml.Reader do
  use Behaviour

  @type type :: atom

  defcallback read(Eml.Readable.t, type) :: Eml.t | Eml.error

end

defimpl Eml.Readable, for: BitString do
  def read(data, reader), do: reader.read(data, BitString)
end

defimpl Eml.Readable, for: Integer do
  def read(data, reader), do: reader.read(data, Integer)
end

defimpl Eml.Readable, for: Float do
  def read(data, reader), do: reader.read(data, Float)
end

defimpl Eml.Readable, for: Tuple do
  def read(data, reader), do: reader.read(data, Tuple)
end

defimpl Eml.Readable, for: Atom do
  def read(nil, _reader),   do: nil
  def read(true, reader),   do: reader.read(true, Atom)
  def read(false, reader),  do: reader.read(false, Atom)
  def read(param, _reader), do: Eml.Parameter.new(param)
end

defimpl Eml.Readable, for: [Eml.Content, Eml.Markup, Eml.Parameter, Eml.Template] do
  def read(data, _reader), do: data
end

defimpl Eml.Readable, for: [Function, PID, Port, Reference, List] do
  def read(data, _reader), do: { :error, "Unreadable data: #{inspect data}" }
end
