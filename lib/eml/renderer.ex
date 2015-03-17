defmodule Eml.Renderer do
  @moduledoc """
  Various helper functions for implementing an Eml renderer.
  """

  # Options helper

  @default_opts %{prerender: nil,
                  postrender: nil}

  def new_opts(opts \\ %{}), do: Dict.merge(@default_opts, opts)
  # State helper

  @default_state %{type: :content,
                   chunks: [],
                   current_tag: nil}

  def new_state(state \\ %{}), do: Dict.merge(@default_state, state)

  # Content helpers

  def default_render_content(node, opts, %{chunks: chunks} = s) when is_binary(node) do
    %{s| chunks: [maybe_prerender(node, opts) | chunks]}
  end

  def default_render_content(node, opts, %{chunks: chunks} = s) when is_tuple(node) do
    %{s| type: :quoted, chunks: [maybe_prerender(node, opts) | chunks] }
  end

  def default_render_content(%Eml.Element{template: fun} = el, opts, %{chunks: chunks} = s) when is_function(fun) do
    case Eml.Element.apply_template(el) do
      node when is_binary(node) ->
        %{s| chunks: [maybe_prerender(node, opts) | chunks]}
      node  ->
        %{s| type: :quoted, chunks: [maybe_prerender(node, opts) | chunks]}
    end
  end

  def default_render_content(data, _, _) do
    raise Eml.CompileError, type: :unsupported_content_type, value: data
  end

  def maybe_prerender(node, %{prerender: fun}) when is_function(fun) do
    fun.(node)
  end
  def maybe_prerender(node, _opts) do
    node
  end

  # Attribute helpers

  def default_render_attr_value(value, _opts, %{chunks: chunks} = s) when is_binary(value) do
    %{s| chunks: [value | chunks]}
  end

  def default_render_attr_value(value, _opts, %{chunks: chunks} = s) when is_tuple(value) do
    %{s| type: :quoted, chunks: [value | chunks]}
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

  entity_map = %{"&" => "&amp;",
                 "<" => "&lt;",
                 ">" => "&gt;",
                 "\"" => "&quot;",
                 "'" => "&#39;",
                 "…" => "&hellip;"}

  def escape(eml) do
    Eml.transform(eml, fn
      node when is_binary(node) ->
        escape(node, "")
      node ->
        node
    end)
  end

  for {char, entity} <- entity_map do
    defp escape(unquote(char) <> rest, acc) do
      escape(rest, acc <> unquote(entity))
    end
  end
  defp escape(<<char::utf8, rest::binary>>, acc) do
    escape(rest, acc <> <<char>>)
  end
  defp escape("", acc) do
    acc
  end


  # Chunk helpers

  def chunk_type(_, :quoted), do: :quoted
  def chunk_type(type, _),   do: type

  # Create final result.

  def to_result(%{type: type, chunks: chunks}, %{postrender: fun} = opts, renderer) do
    chunks
    |> maybe_postrender(fun)
    |> create_result(type, renderer, opts)
  end

  defp maybe_postrender(chunks, nil) do
    chunks
  end
  defp maybe_postrender(chunks, fun) when is_function(fun) do
    fun.(chunks)
  end

  defp create_result(chunks, :quoted, renderer, opts) do
    create_quoted(chunks, [], renderer, opts)
  end
  defp create_result(chunks, _type, _renderer, _opts) do
    chunks |> :lists.reverse() |> IO.iodata_to_binary()
  end

  defp create_quoted([chunk | rest], [h | t], renderer, opts) when is_binary(chunk) and is_binary(h) do
    create_quoted(rest, [chunk <> h | t], renderer, opts)
  end
  defp create_quoted([chunk | rest], buffer, renderer, opts) when is_binary(chunk) do
    create_quoted(rest, [chunk | buffer], renderer, opts)
  end
  defp create_quoted([expr | rest], buffer, renderer, opts) do
    opts = Dict.put(opts, :renderer, renderer)
    expr = Macro.prewalk(expr, fn term ->
      term
      |> handle_unquoted_assign()
      |> EEx.Engine.handle_assign()
    end)
    expr = quote do
      Eml.compile(Eml.encode(unquote(expr)), unquote(Macro.escape(opts)))
    end
    create_quoted(rest, [expr | buffer], renderer, opts)
  end
  defp create_quoted([], buffer, _renderer, _opts) do
    buffer
  end

  def finalize_chunks(chunks) do
    case finalize_chunks(chunks, []) do
      [node]  ->
        node
      nodes ->
        nodes |> :lists.reverse()
    end
  end

  defp finalize_chunks([chunk | rest], [h | t]) when is_binary(chunk) and is_binary(h) do
    finalize_chunks(rest, [h <> chunk | t])
  end
  defp finalize_chunks([chunks | rest], acc) when is_list(chunks) do
    finalize_chunks(rest, finalize_chunks(chunks, acc))
  end
  defp finalize_chunks([chunk | rest], acc) do
    finalize_chunks(rest, [chunk | acc])
  end
  defp finalize_chunks([], acc) do
    acc
  end

  def handle_unquoted_assign({:&, _, [{:@, meta, [{name, _, atom}]}]}) when is_atom(name) and is_atom(atom) do
    line = meta[:line] || 0
    assign = quote line: line do
      @unquote(Macro.var(name, nil))
    end
    Macro.escape(assign)
  end
  def handle_unquoted_assign(term) do
    term
  end
end
