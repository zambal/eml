defmodule Eml.Element.Generator do
  @moduledoc """
  This module defines some macro's and helper functions
  for generating Eml element macro's.

  ### Example

      iex> defmodule MyElements do
      ...>   use Eml.Element.Generator tags: [:custom1, :custom2]
      ...> end
      iex> import MyElements
      iex> custom1 [id: 42], "content in a custom element"
      #custom1<%{id: "42"} ["content in a custom element"]>
  """

  defmacro __using__(opts) do
    tags = opts[:tags] || []
    quote do
      defmacro __using__(_) do
        mod = __MODULE__
        ambiguous_imports = Eml.Element.Generator.find_ambiguous_imports(unquote(tags))
        quote do
          import Kernel, except: unquote(ambiguous_imports)
          import unquote(mod)
        end
      end
      Enum.each(unquote(tags), fn tag ->
        Eml.Element.Generator.def_element(tag)
      end)
    end
  end

  @doc false
  defmacro def_element(tag) do
    quote bind_quoted: [tag: tag] do
      defmacro unquote(tag)(content_or_attrs, maybe_content \\ nil) do
        tag = unquote(tag)
        in_match = Macro.Env.in_match?(__CALLER__)
        { attrs, content } = Eml.Element.Generator.extract_content(content_or_attrs, maybe_content, in_match)
        if in_match do
          quote do
            %Eml.Element{tag: unquote(tag), attrs: unquote(attrs), content: unquote(content)}
          end
        else
          quote do
            Eml.Element.new(unquote(tag), unquote(attrs), unquote(content))
          end
        end
      end
    end
  end

  @doc false
  def find_ambiguous_imports(tags) do
    default_imports = Kernel.__info__(:functions) ++ Kernel.__info__(:macros)
    for { name, arity } <- default_imports, arity in 1..2 and name in tags do
      { name, arity }
    end
  end

  @doc false
  def extract_content(content_or_attrs, maybe_content, in_match) do
    init = fn
      nil, content, true ->
        { (quote do: _), content }
      nil, content, false ->
        { (quote do: %{}), content }
      attrs, nil, true ->
        { attrs, quote do: _ }
      attrs, nil, false ->
        { attrs, [] }
      attrs, content, _ ->
        { attrs, content }
    end
    case { content_or_attrs, maybe_content } do
      { [{ :do, {:"__block__", _, content}}], _ }     -> init.(nil, content, in_match)
      { [{ :do, content}], _ }                        -> init.(nil, content, in_match)
      { attrs, [{ :do, {:"__block__", _, content}}] } -> init.(attrs, content, in_match)
      { attrs, [{ :do, content}] }                    -> init.(attrs, content, in_match)
      { [{ _, _ } | _] = attrs, nil }                 -> init.(attrs, nil, in_match)
      { attrs, nil } when in_match                    -> init.(attrs, nil, in_match)
      { content, nil } when not in_match              -> init.(nil, content, in_match)
      { attrs, content }                              -> init.(attrs, content, in_match)
    end
  end
end
