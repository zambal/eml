defmodule Eml.Parser do
  @moduledoc """
  Various helper functions for implementing an Eml parser.
  """

  # Entity helpers

  entity_map = %{"&amp;"    => "&",
                 "&lt;"     => "<",
                 "&gt;"     => ">",
                 "&quot;"   => "\"",
                 "&hellip;" => "…"}
  entity_map = for n <- 32..126, into: entity_map do
    { "&##{n};", <<n>> }
  end

  def unescape(eml) do
    Eml.transform(eml, fn
      node when is_binary(node) ->
        unescape(node, "")
      node ->
        node
    end)
  end

  for {entity, char} <- entity_map do
    defp unescape(unquote(entity) <> rest, acc) do
      unescape(rest, acc <> unquote(char))
    end
  end
  defp unescape(<<char::utf8, rest::binary>>, acc) do
    unescape(rest, acc <> <<char>>)
  end
  defp unescape("", acc) do
    acc
  end
end
