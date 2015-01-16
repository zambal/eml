defmodule Eml.Language.Native do
  @behaviour Eml.Language

  def markup?(), do: false

  def parse(data, BitString) do
    data
  end

  def parse(data, Atom) do
    Atom.to_string(data)
  end

  def parse(data, Integer) do
    Integer.to_string(data)
  end

  def parse(data, Float) do
    Float.to_string(data)
  end

  def parse({ :escaped, string }, Tuple) do
    { :escaped, string }
  end
  def parse(data, Tuple) do
    { :error, "Unparsable data: #{inspect data}" }
  end


  def render(data, _opts), do: data
end
