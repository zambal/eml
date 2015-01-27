defmodule Eml.Language.Native do
  @moduledoc false

  @behaviour Eml.Language

  def element?(), do: false

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

  def render(data, _opts), do: data
end
