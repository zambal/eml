defmodule Eml.Markup.Generator do
  @moduledoc """
  This module defines some macro's and helper functions
  for creating Eml element macro's.

  ### Example

      iex> defmodule MyElements do
      ...>   use Eml.Markup.Generator tags: [:custom1, :custom2]
      ...> end
      iex> import MyElements
      iex> eml do: custom1 [id: 42], "content in a custom element"
      #custom1<%{id: "42"} ["content in a custom element"]>
  """

  defmacro __using__(opts) do
    tags = opts[:tags] || []
    quote do
      Enum.each(unquote(tags), fn tag ->
        unquote(__MODULE__).def_markup(tag)
      end)
    end
  end

  @doc false
  defmacro def_markup(tag) do
    quote bind_quoted: [tag: tag] do
      defmacro unquote(tag)(content_or_attrs, maybe_content \\ []) do
        tag = unquote(tag)
        { attrs, content } = Eml.Markup.Generator.extract_content(content_or_attrs, maybe_content)
        if Macro.Env.in_match?(__CALLER__) do
          quote do
            %Eml.Markup{tag: unquote(tag), attrs: unquote(attrs), content: unquote(content)}
          end
        else
          quote do
            Eml.Markup.new(unquote(tag), unquote(attrs), unquote(content))
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
      { attrs, content }                              -> { attrs, content }
    end
  end
end
