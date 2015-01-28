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
      Enum.each(unquote(tags), fn tag ->
        unquote(__MODULE__).def_element(tag)
      end)
    end
  end

  @doc false
  defmacro def_element(tag) do
    quote bind_quoted: [tag: tag] do
      defmacro unquote(tag)(content_or_attrs, maybe_content \\ []) do
        tag = unquote(tag)
        { attrs, content } = Eml.Element.Generator.extract_content(content_or_attrs, maybe_content)
        if Macro.Env.in_match?(__CALLER__) do
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
  def extract_content(content_or_attrs, maybe_content) do
    case { content_or_attrs, maybe_content } do
      { [{ :do, {:"__block__", _, content}}], _ }     -> { (quote do: %{}), content }
      { [{ :do, content}], _ }                        -> { (quote do: %{}), content }
      { attrs, [{ :do, {:"__block__", _, content}}] } -> { attrs, content }
      { attrs, [{ :do, content}] }                    -> { attrs, content }
      { [{ _, _ } | _] = attrs, [] }                  -> { attrs, [] }
      { content, [] }                                 -> { (quote do: %{}), content }
      { attrs, content }                              -> { attrs, content }
    end
  end
end
