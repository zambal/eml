defmodule Eml.Language.Native do
  @behaviour Eml.Language

  def markup?(), do: false

  def read(data, BitString) do
    data
  end

  def read(data, Atom) do
    Atom.to_string(data)
  end

  def read(data, Integer) do
    Integer.to_string(data)
  end

  def read(data, Float) do
    Float.to_string(data)
  end

  def read(data, Tuple) do
    { :error, "Unreadable data: #{inspect data}" }
  end

  def write(data, _opts), do: data
end
