defmodule Eml.Readers.Native do
  @behaviour Eml.Reader

  def read(data, BitString) do
    data
  end

  def read(data, Atom) do
    atom_to_binary(data)
  end

  def read(data, Integer) do
    integer_to_binary(data)
  end

  def read(data, Float) do
    float_to_binary(data)
  end

  def read(data, Tuple) do
    { :error, "Unreadable data: #{inspect data}" }
  end

end