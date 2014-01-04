defmodule Eml.Markup.Generator do
  @moduledoc false

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
      defmacro unquote(tag)(attrs // [], content) do
        tag = unquote(tag)
        markup = Eml.Markup.Generator.extract_args(tag, content, attrs)
        quote do
          Eml.Markup.new(unquote(markup))
        end
      end
    end
  end

  @doc false
  def extract_args(tag, content, attrs) do
    content =
      case content do
        [{ :do, {:"__block__", _, content}}] -> content
        [{ :do, content}]                    -> content
        content                              -> content
      end
    { id, attrs } = Keyword.pop(attrs, :id)
    { class, attrs } = Keyword.pop(attrs, :class)
    [tag: tag, id: id, class: class, attrs: attrs, content: content]
  end

end