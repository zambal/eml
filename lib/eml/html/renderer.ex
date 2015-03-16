defmodule Eml.HTML.Renderer do
  @moduledoc false

  import Eml.Renderer
  alias Eml.Element

  # API

  def render(eml, opts) do
    opts = Dict.merge([quotes: :single], opts) |> new_opts()
    type = if opts.mode == :compile, do: :quoted, else: :content
    render_content(eml, opts, new_state(type: type)) |> to_result(opts, Eml.HTML.Renderer)
  end

  # Eml parsing

  defp render_content(%Element{template: nil} = el, opts, %{type: type, chunks: chunks}) do
    %Element{tag: tag, attrs: attrs, content: content} = maybe_prerender(el, opts)
    type  = chunk_type(:element, type)

    chunks = chunks
             |> maybe_doctype(tag)
             |> start_tag_open(tag)
    s = %{chunks: chunks} = render_attrs(attrs, opts, %{type: type, chunks: chunks, current_tag: tag})
    if is_void_element?(tag) do
      chunks = void_tag_close(chunks)
    else
      chunks = start_tag_close(chunks)
      s = %{chunks: chunks} = render_content(content, opts, %{s| chunks: chunks})
      chunks = end_tag(chunks, tag)
    end
    %{s| chunks: chunks}
  end

  defp render_content(list, opts, s) when is_list(list) do
    Enum.reduce(list, s, fn node, s ->
      render_content(node, opts, s)
    end)
  end

  defp render_content(node, %{prerender: fun}, %{chunks: chunks, current_tag: tag} = s) when is_binary(node) do
    %{s| chunks: [maybe_prerender(node, fun) |> maybe_escape(tag) | chunks]}
  end

  defp render_content(node, opts, s) do
    default_render_content(node, opts, s)
  end

  # Attributes parsing

  defp render_attrs(attrs, opts, s) when is_map(attrs) do
    render_attrs(Enum.to_list(attrs), opts, s)
  end

  defp render_attrs([{ _, nil } | rest], opts, s) do
    render_attrs(rest, opts, s)
  end

  defp render_attrs([{ k, v } | rest], opts, %{type: type} = s) do
    type = chunk_type(:attr, type)
    s    = render_attr(k, v, opts, %{s| type: type})
    render_attrs(rest, opts, s)
  end

  defp render_attrs([], _, s), do: s

  defp render_attr(_, nil, _, s), do: s
  defp render_attr(field, value, %{quotes: q} = opts, %{chunks: chunks} = s) do
    quotes_char  = quotes_char(q)
    field  = attr_field(field)
    chunks = [" #{field}=#{quotes_char}" | chunks]
    %{chunks: chunks} = s = render_attr_value(value, opts, %{s| chunks: chunks})
    chunks = ["#{quotes_char}" | chunks]
    %{s| chunks: chunks}
  end

  defp render_attr_value(list, opts, %{chunks: chunks} = s) when is_list(list) do
    attr_s = Enum.reduce(list, new_state(type: :attr), fn value, s  ->
      render_attr_value(value, opts, s)
    end)
    case attr_s do
      %{type: :quoted, chunks: tchunks} ->
        tchunks = insert_whitespace(tchunks)
        %{s| type: :quoted, chunks: tchunks ++ chunks}
      %{chunks: rchunks} ->
        rchunks = insert_whitespace(rchunks)
        %{s| chunks: rchunks ++ chunks}
    end
  end

  defp render_attr_value(value, opts, s) do
    default_render_attr_value(value, opts, s)
  end

  # Element generators

  defp start_tag_open(chunks, tag), do: ["<#{tag}" | chunks]
  defp start_tag_close(chunks),     do: [">" | chunks]
  defp void_tag_close(chunks),     do: ["/>" | chunks]
  defp end_tag(chunks, tag),        do: ["</#{tag}>" | chunks]

  defp maybe_doctype(chunks, :html), do: ["<!doctype html>\n" | chunks]
  defp maybe_doctype(chunks, _),     do: chunks

  # Element helpers

  defp maybe_escape(string, tag)
  when not tag in [:script, :style], do: escape(string)
  defp maybe_escape(string, _tag),   do: string

  defp is_void_element?(tag) do
    tag in [:area, :base, :br, :col, :embed, :hr, :img, :input, :keygen, :link, :meta, :param, :source, :track, :wbr]
  end

  # Attribute element helpers

  defp quotes_char(:single), do: "'"
  defp quotes_char(:double), do: "\""
end
