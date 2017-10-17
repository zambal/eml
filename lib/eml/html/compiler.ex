defmodule Eml.HTML.Compiler do
  @moduledoc false

  alias Eml.Compiler
  alias Eml.Element
  import Eml.Compiler, only: [add_chunk: 2]

  def opts do
    [quotes: :single]
  end

  # Eml parsing

  def compile_node(%Element{tag: tag, attrs: attrs, content: content, template: nil}, opts, chunks) do
    chunks = chunks |> maybe_doctype(tag) |> start_tag_open(tag)
    chunks = Compiler.compile_attrs(attrs, opts, chunks)
    if is_void_element?(tag) do
      void_tag_close(chunks)
    else
      chunks = start_tag_close(chunks)
      chunks = Compiler.compile_node(content, opts, chunks)
      end_tag(chunks, tag)
    end
  end

  def compile_node(_, _, _) do
    :unhandled
  end

  def compile_attr(field, value, opts, chunks) do
    quotes_char = quotes_char(opts[:quotes])
    field = attr_field(field)
    chunks = add_chunk(" #{field}=#{quotes_char}", chunks)
    chunks = Compiler.compile_attr_value(value, opts, chunks)
    add_chunk("#{quotes_char}", chunks)
  end

  defp attr_field(field) do
    field = Atom.to_string(field)
    if String.starts_with?(field, "_"),
      do: "data-" <> String.trim_leading(field, "_"),
    else: field
  end

  def compile_attr_value(_, _, _) do
    :unhandled
  end

  # Element generators

  defp start_tag_open(chunks, tag), do: add_chunk("<#{tag}", chunks)
  defp start_tag_close(chunks),     do: add_chunk(">", chunks)
  defp void_tag_close(chunks),      do: add_chunk("/>", chunks)
  defp end_tag(chunks, tag),        do: add_chunk("</#{tag}>", chunks)

  defp maybe_doctype(chunks, :html), do: add_chunk("<!doctype html>\n", chunks)
  defp maybe_doctype(chunks, _),     do: chunks

  # Element helpers

  defp is_void_element?(tag) do
    tag in [:area, :base, :br, :col, :embed, :hr, :img, :input, :keygen, :link, :meta, :param, :source, :track, :wbr]
  end

  # Attribute element helpers

  defp quotes_char(:single), do: "'"
  defp quotes_char(:double), do: "\""
end
