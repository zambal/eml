defmodule Eml.Parser do
  @moduledoc """
  Various helper functions for implementing an Eml parser.
  """

  # Entity helpers

  @entity_map %{"amp"    => "&",
                "lt"     => "<",
                "gt"     => ">",
                "quot"   => "\"",
                "#39"    => "'",
                "hellip" => "…"}

  def get_entity(chars) do
    entities = Map.keys(@entity_map)
    max_length = Enum.reduce(entities, 0, fn e, acc ->
      length = String.length(e)
      if length > acc, do: length, else: acc
    end)
    case get_entity(chars, "", entities, max_length) do
      { e, rest } -> { @entity_map[e], rest }
      nil         -> { "&", chars }
    end
  end

  def get_entity(<<";", rest::binary>>, acc, entities, _) do
    if acc in entities do
      { acc, rest }
    end
  end
  def get_entity(<<char, rest::binary>>, acc, entities, max_length) do
    acc = acc <> <<char>>
    unless String.length(acc) > max_length do
      get_entity(rest, acc, entities, max_length)
    end
  end
  def get_entity("", _, _, _), do: nil

  # Attribute helper

  def class_value(nil), do: nil
  def class_value(value) do
    case String.split(value, " ") do
      [class] -> class
      classes -> classes
    end
  end
end
