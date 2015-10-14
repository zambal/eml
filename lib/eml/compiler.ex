defmodule Eml.Compiler do
  @moduledoc """
  Various helper functions for implementing an Eml compiler.
  """

  @type chunk :: String.t | { :safe, String.t } | Macro.t

  # Options helper

  @default_opts %{escape: true,
                  transform: nil,
                  fragment: false,
                  compiler: Eml.HTML.Compiler}

  defp new_opts(opts), do: Dict.merge(@default_opts, opts)

  # API

  @doc """
  Compiles eml to a string, or a quoted expression when the input contains
  contains quoted expressions too.

  Accepts the same options as `Eml.render/3`

  In case of error, raises an Eml.CompileError exception.

  ### Examples:

      iex> Eml.Compiler.compile(body(h1(id: "main-title")))
      {:safe, "<body><h1 id='main-title'></h1></body>"

  """

  @spec compile(Eml.t, Dict.t) :: { :safe, String.t } | Macro.t
  def compile(eml, opts \\ %{}) do
    opts = new_opts(opts)
    opts = Dict.merge(opts.compiler.opts(), opts)
    compile_node(eml, opts, []) |> to_result(opts)
  end

  @spec precompile(Macro.Env.t, Dict.t) :: { :safe, String.t } | Macro.t
  def precompile(env \\ %Macro.Env{}, opts) do
      mod_opts = if mod = env.module,
                 do: Module.get_attribute(mod, :eml_compile) |> Macro.escape(),
                 else: []
      opts = Keyword.merge(mod_opts, opts)
    { file, opts } = Keyword.pop(opts, :file)
    { block, opts } = Keyword.pop(opts, :do)
    ast = if file do
            string = File.read!(file)
            Code.string_to_quoted!(string, file: file, line: 1)
          else
            block
          end |> prewalk(opts[:fragment])
    { expr, _ } = Code.eval_quoted(ast, [], env)
    { opts, _ } = Code.eval_quoted(opts, [], env)
    compile(expr, opts)
  end

  # Content parsing

  @spec compile_node(Eml.t, map, [chunk]) :: [chunk]
  def compile_node(list, opts, chunks) when is_list(list) do
    Enum.reduce(list, chunks, fn node, chunks ->
      compile_node(node, opts, chunks)
    end)
  end

  def compile_node(node, opts, chunks) do
    node = node
    |> maybe_transform(opts)
    |> Eml.Encoder.encode()
    case opts.compiler.compile_node(node, opts, chunks) do
      :unhandled ->
        default_compile_node(node, opts, chunks)
      s ->
        s
    end
  end

  @spec default_compile_node(Eml.node_primitive, map, [chunk]) :: [chunk]
  defp default_compile_node(node, opts, chunks) when is_binary(node) do
    add_chunk(maybe_escape(node, opts), chunks)
  end

  defp default_compile_node({ :safe, node }, _opts, chunks) when is_binary(node) do
    add_chunk(node, chunks)
  end

  defp default_compile_node(node, _opts, chunks) when is_tuple(node) do
    add_chunk(node, chunks)
  end

  defp default_compile_node(%Eml.Element{template: fun} = node, opts, chunks) when is_function(fun) do
    node |> Eml.Element.apply_template() |> compile_node(opts, chunks)
  end

  defp default_compile_node(nil, _opts, chunks) do
    chunks
  end

  defp default_compile_node(node, _, _) do
    raise Eml.CompileError, message: "Bad node primitive: #{inspect node}"
  end

  # Attributes parsing

  @spec compile_attrs(Eml.Element.attrs, map, [chunk]) :: [chunk]
  def compile_attrs(attrs, opts, chunks) when is_map(attrs) do
    Enum.reduce(attrs, chunks, fn
      { _, nil }, chunks -> chunks
      { k, v }, chunks   -> compile_attr(k, v, opts, chunks)
    end)
  end

  @spec compile_attr(atom, Eml.t, map, [chunk]) :: [chunk]
  def compile_attr(field, value, opts, chunks) do
    opts.compiler.compile_attr(field, value, opts, chunks)
  end

  @spec compile_attr_value(Eml.t, map, [chunk]) :: [chunk]
  def compile_attr_value(list, opts, chunks) when is_list(list) do
    Enum.reduce(list, chunks, fn value, chunks ->
      compile_attr_value(value, opts, chunks)
    end)
  end

  def compile_attr_value(value, opts, chunks) do
    value = Eml.Encoder.encode(value)
    case opts.compiler.compile_attr_value(value, opts, chunks) do
      :unhandled ->
        default_compile_node(value, opts, chunks)
      s ->
        s
    end
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
    escape(rest, acc <> <<char::utf8>>)
  end
  defp escape("", acc) do
    acc
  end

  # Create final result.

  defp to_result([{ :safe, string }], _opts) do
    { :safe, string }
  end
  defp to_result(chunks, opts) do
    template = :lists.reverse(chunks)
    if opts.fragment do
      template
    else
      quote do
        Eml.Compiler.concat(unquote(template), unquote(Macro.escape(opts)))
      end
    end
  end

  def maybe_transform(node, %{transform: fun}) when is_function(fun), do: fun.(node)
  def maybe_transform(node, _opts), do: node

  def maybe_escape(node, %{escape: true}), do: escape(node, "")
  def maybe_escape(node, _opts), do: node

  def add_chunk(chunk, [{:safe, safe_chunk} | rest]) when is_binary(chunk) do
    [{:safe, safe_chunk <> chunk } | rest]
  end
  def add_chunk(chunk, chunks) when is_binary(chunk) do
    [{ :safe, chunk } | chunks]
  end
  def add_chunk(chunk, chunks) do
    [chunk | chunks]
  end

  def concat(buffer, opts) do
    try do
      { :safe, concat(buffer, "", opts) }
    catch
      :throw, { :illegal_quoted, stacktrace } ->
        reraise Eml.CompileError,
        [message: "It's only possible to pass assigns to templates or components when using &"],
        stacktrace
    end
  end

  defp concat({ :safe, chunk }, acc, _opts) do
    acc <> chunk
  end
  defp concat(chunk, acc, opts) when is_binary(chunk) do
    acc <> maybe_escape(chunk, opts)
  end
  defp concat([chunk | rest], acc, opts) do
    concat(rest, concat(chunk, acc, opts), opts)
  end
  defp concat([], acc, _opts) do
    acc
  end
  defp concat(nil, acc, _opts) do
    acc
  end
  defp concat(node, acc, opts) do
    case Eml.Compiler.compile(node, opts) do
      { :safe, chunk } ->
        acc <> chunk
      _ ->
        throw { :illegal_quoted, System.stacktrace() }
    end
  end

  def prewalk(quoted, fragment?) do
    handler = if fragment?,
              do: &handle_fragment/1,
              else: &handle_template/1
    Macro.prewalk(quoted, handler)
  end

  defp handle_fragment({ :@, _, [{ name, _, atom }] } = ast) when is_atom(name) and is_atom(atom) do
    Macro.escape(EEx.Engine.handle_assign(ast))
  end
  defp handle_fragment({ :&, _meta, [{ _fun, _, args }] } = ast) do
    case Macro.prewalk(args, false, &handle_capture_args/2) do
      { _, true } ->
        ast
      { _, false } ->
        raise Eml.CompileError,
        message: "It's not possible to use & inside fragments"
    end
  end
  defp handle_fragment(arg) do
    arg
  end

  defp handle_template({ :&, meta, [{ fun, _, args }] }) do
    case Macro.prewalk(args, false, &handle_capture_args/2) do
      { _, true } ->
        raise Eml.CompileError,
        message: "It's not possible to use & for captures inside templates or components"
      { new_args, false } ->
        line = Keyword.get(meta, :line, 0)
        Macro.escape(quote line: line do
          unquote(fun)(unquote_splicing(List.wrap(new_args)))
        end)
    end
  end
  defp handle_template({ :@, meta, [{ name, _, atom }]}) when is_atom(name) and is_atom(atom) do
    line = Keyword.get(meta, :line, 0)
    Macro.escape(quote line: line do
      Eml.Compiler.get_assign(unquote(name), var!(assigns), var!(funs))
    end)
  end
  defp handle_template(ast) do
    ast
  end

  defp handle_capture_args({ :@, meta, [{ name, _, atom }]}, regular_capure?) when is_atom(name) and is_atom(atom) do
    line = Keyword.get(meta, :line, 0)
    ast = quote line: line do
      Eml.Compiler.get_assign(unquote(name), var!(assigns), var!(funs))
    end
    { ast, regular_capure? }
  end
  defp handle_capture_args({ :&, _meta, [num]} = ast, _regular_capure?) when is_integer(num) do
    { ast, true }
  end
  defp handle_capture_args({ :/, _meta, _args} = ast, _regular_capure?) do
    { ast, true }
  end
  defp handle_capture_args(ast, regular_capure?) do
    { ast, regular_capure? }
  end

  @doc false
  def get_assign(key, assigns, funs) do
    x = Dict.get(assigns, key)
    case Keyword.get(funs, key) do
      nil -> x
      fun -> fun.(x)
    end
  end
end
