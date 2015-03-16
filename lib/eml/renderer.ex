defmodule Eml.Renderer do
  @moduledoc """
  Various helper functions for implementing an Eml renderer.
  """

  # Options helper

  @default_opts %{prerender: nil,
                  postrender: nil,
                  mode: :render}

  def new_opts(opts \\ %{}), do: Dict.merge(@default_opts, opts)
  # State helper

  @default_state %{type: :content,
                   chunks: [],
                   current_tag: nil}

  def new_state(state \\ %{}), do: Dict.merge(@default_state, state)

  # Content helpers

  def default_render_content({ :quoted, quoted }, opts, %{chunks: chunks} = s) do
    %{s| type: :quoted, chunks: :lists.reverse(maybe_prerender(quoted, opts)) ++ chunks }
  end

  def default_render_content({ :safe, node }, opts, %{chunks: chunks} = s) do
    %{s| chunks: [maybe_prerender(node, opts) | chunks]}
  end

  def default_render_content(%Eml.Element{template: fun} = el, opts, %{chunks: chunks} = s) when is_function(fun) do
    case Eml.Element.apply_template(el) do
      { :quoted, quoted } ->
        %{s| type: :quoted, chunks: :lists.reverse(maybe_prerender(quoted, opts)) ++ chunks}
      { :safe, string } ->
        %{s| chunks: [maybe_prerender(string, opts) | chunks]}
    end
  end

  def default_render_content(node, %{prerender: fun}, %{chunks: chunks} = s) when is_binary(node) do
    %{s| chunks: [maybe_prerender(node, fun) |> escape() | chunks]}
  end

  def default_render_content(data, _, _) do
    raise Eml.CompileError, type: :unsupported_content_type, value: data
  end

  def maybe_prerender(node, nil) do
    node
  end
  def maybe_prerender(node, %{prerender: nil}) do
    node
  end
  def maybe_prerender(node, fun) when is_function(fun) do
    fun.(node)
  end
  def maybe_prerender(node, %{prerender: fun}) when is_function(fun) do
    fun.(node)
  end

  # Attribute helpers

  def default_render_attr_value({ :quoted, quoted }, _opts, %{chunks: chunks} = s) do
    %{s| type: :quoted, chunks: :lists.reverse(quoted) ++ chunks}
  end

  def default_render_attr_value({ :safe, value }, _opts, %{chunks: chunks} = s) do
    %{s| chunks: [value | chunks]}
  end

  def default_render_attr_value(value, _opts, %{chunks: chunks} = s) when is_binary(value) do
    %{s| chunks: [escape(value) | chunks]}
  end

  def default_render_attr_value(value, _, _) do
    raise Eml.CompileError, type: :unsupported_attribute_type, value: value
  end

  def attr_field(field) do
    field = Atom.to_string(field)
    if String.starts_with?(field, "_"),
      do: "data-" <> String.lstrip(field, ?_),
    else: field
  end

  def insert_whitespace(values) do
    insert_whitespace(values, [])
  end
  def insert_whitespace([v], acc) do
    :lists.reverse([v | acc])
  end
  def insert_whitespace([v | rest], acc) do
    insert_whitespace(rest, [" ", v | acc])
  end
  def insert_whitespace([], acc) do
    acc
  end

  # Text escaping

  def escape(s) do
    s
    |> :binary.replace("&", "&amp;", [:global])
    |> :binary.replace("<", "&lt;", [:global])
    |> :binary.replace(">", "&gt;", [:global])
    |> :binary.replace("'", "&#39;", [:global])
    |> :binary.replace("\"", "&quot;", [:global])
  end

  # Chunk helpers

  def chunk_type(_, :quoted), do: :quoted
  def chunk_type(type, _),   do: type

  # Create final result.

  def to_result(%{type: type, chunks: chunks}, %{postrender: fun} = opts, renderer) do
    chunks
    |> maybe_postrender(fun)
    |> maybe_quoted(type)
    |> generate_buffer(renderer, opts)
  end

  defp maybe_quoted(chunks, :quoted) do
    { :quoted, chunks }
  end
  defp maybe_quoted(chunks, _) do
    chunks
  end

  defp maybe_postrender(chunks, nil) do
    chunks
  end
  defp maybe_postrender(chunks, fun) when is_function(fun) do
    fun.(chunks)
  end

  defp generate_buffer({ :quoted, chunks }, renderer, opts) do
    { :quoted, generate_buffer(chunks, [], renderer, opts) }
  end
  defp generate_buffer(chunks, _renderer, _opts) do
    { :safe, chunks |> :lists.reverse() |> IO.iodata_to_binary() }
  end

  defp generate_buffer([chunk | rest], [{ :safe, h } | t], renderer, opts) when is_binary(chunk) do
    generate_buffer(rest, [{ :safe, chunk <> h } | t], renderer, opts)
  end
  defp generate_buffer([chunk | rest], buffer, renderer, opts) when is_binary(chunk) do
    generate_buffer(rest, [{ :safe, chunk } | buffer], renderer, opts)
  end
  defp generate_buffer([{ :safe, chunk } | rest], [{ :safe, h } | t], renderer, opts) do
    generate_buffer(rest, [{ :safe, chunk <> h } | t], renderer, opts)
  end
  defp generate_buffer([{ :safe, chunk } | rest], buffer, renderer, opts) do
    generate_buffer(rest, [{ :safe, chunk } | buffer], renderer, opts)
  end
  defp generate_buffer([expr | rest], buffer, renderer, opts) do
    opts = opts
    |> Dict.put(:mode, :render)
    |> Dict.put(:renderer, renderer)
    expr = Macro.prewalk(expr, &EEx.Engine.handle_assign/1)
    expr = quote do
      Eml.render(Eml.encode(unquote(expr)), unquote(Macro.escape(opts)))
    end
    generate_buffer(rest, [expr | buffer], renderer, opts)
  end
  defp generate_buffer([], buffer, _renderer, _opts) do
    buffer
  end

  def finalize_chunks(chunks) do
    case finalize_chunks(chunks, []) do
      [{ :safe, string }] ->
        { :safe, string }
      quoted ->
        { :quoted, quoted }
    end
  end

  defp finalize_chunks([{ :safe, chunk } | rest], [{ :safe, h } | t]) do
    finalize_chunks(rest, [{ :safe, h <> chunk } | t])
  end
  defp finalize_chunks([chunks | rest], acc) when is_list(chunks) do
    finalize_chunks(rest, finalize_chunks(chunks, acc))
  end
  defp finalize_chunks([], acc) do
    acc
  end
  defp finalize_chunks([{ :quoted, chunks } | rest], acc)  do
    finalize_chunks(rest, finalize_chunks(chunks, acc))
  end
  defp finalize_chunks([chunk | rest], acc) do
    finalize_chunks(rest, [chunk | acc])
  end
end
