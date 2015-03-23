defmodule Eml.Compiler do
  @moduledoc """
  Various helper functions for implementing an Eml compiler.
  """

  @type chunk :: String.t | { :safe, String.t } | Eml.Element.t | Macro.t

  # Options helper

  @default_opts %{escape: true,
                  transform: nil,
                  fragment: false,
                  handle_assigns: true,
                  compiler: Eml.HTML.Compiler}

  defp new_opts(opts), do: Dict.merge(@default_opts, opts)

  # API

  @doc """
  Compiles eml to a quoted expression.

  Accepts the same options as `Eml.render/3` and its result
  can be rendered to a string with a subsequent call to `Eml.render/3`.

  In case of error, raises an Eml.CompileError exception.

  ### Examples:

      iex> t = Eml.compile(body(h1([id: "main-title"], :the_title)))
      ["<body><h1 id='main-title'>",
        {{:., [], [{:__aliases__, [alias: false], [:Eml]}, :compile]}, [],
         [{{:., [], [{:__aliases__, [alias: false], [:Eml]}, :encode]}, [],
           [{:the_title, [line: 4], nil}]},
          {:%{}, [],
           [quotes: :single, compiler: Eml.HTML.Compiler]}]}, "</h1></body>"]
            iex> t.chunks
            ["<body><h1 id='main-title'>", #param:the_title, "</h1></body>"]
      iex> Eml.compile(t, the_title: "The Title")
      "<body><h1 id='main-title'>The Title</h1></body>"

  """

  @spec compile(Eml.t, Dict.t) :: { :safe, String.t } | Macro.t
  def compile(eml, opts \\ %{}) do
    opts = new_opts(opts)
    opts = Dict.merge(opts.compiler.opts(), opts)
    compile_node(eml, opts, []) |> to_result(opts)
  end

  @spec precompile(Macro.Env.t | Keyword.t, Dict.t) :: { :safe, String.t } | Macro.t
  def precompile(env \\ [], opts) do
    { file, opts } = Keyword.pop(opts, :file)
    { block, opts } = Keyword.pop(opts, :do)
    Keyword.put(opts, :handle_assigns, false)
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

  defp default_compile_node(node, opts, chunks) when is_binary(node) do
    add_chunk(maybe_escape(node, opts), chunks)
  end

  defp default_compile_node({ :safe, node }, _opts, chunks) when is_binary(node) do
    add_chunk(node, chunks)
  end

  defp default_compile_node(node, opts, chunks) when is_tuple(node) do
    node = case opts do
             %{handle_assigns: true, fragment: false} ->
               Macro.prewalk(node, &handle_template_assign/1)
             %{handle_assigns: true, fragment: true} ->
               Macro.prewalk(node, &EEx.Engine.handle_assign/1)
             _ ->
               node
           end
    add_chunk(node, chunks)
  end

  defp default_compile_node(%Eml.Element{template: fun} = node, opts, chunks) when is_function(fun) do
    node |> Eml.Element.apply_template() |> compile_node(opts, chunks)
  end

  defp default_compile_node(nil, _opts, chunks) do
    chunks
  end

  defp default_compile_node(node, _, _) do
    raise Eml.CompileError, type: :unsupported_node_type, value: node
  end

  # Attributes parsing

  def compile_attrs(attrs, opts, chunks) when is_map(attrs) do
    Enum.reduce(attrs, chunks, fn
      { _, nil }, chunks -> chunks
      { k, v }, chunks   -> compile_attr(k, v, opts, chunks)
    end)
  end

  def compile_attr(field, value, opts, chunks) do
    opts.compiler.compile_attr(field, value, opts, chunks)
  end

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
    escape(rest, acc <> <<char>>)
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
      :throw, :illegal_quoted ->
        raise Eml.CompileError,
        type: :illegal_quoted,
        value: "It's not possible to pass quoted expressions to templates, components and Eml.render/3"
    end
  end

  defp concat({ :safe, chunk }, acc, _opts) do
    acc <> chunk
  end
  defp concat(chunk, acc, opts) when is_binary(chunk) do
    acc <> maybe_escape(chunk, opts)
  end
  defp concat(chunks, acc, opts) when is_list(chunks) do
    Enum.reduce(chunks, acc, &concat(&1, &2, opts))
  end
  defp concat(node, acc, opts) do
    case Eml.Compiler.compile(node, opts) do
      { :safe, chunk } ->
        acc <> chunk
      _ ->
        throw :illegal_quoted
    end
  end

  defp prewalk(quoted, fragment?) do
    if fragment? do
      case Macro.prewalk(quoted, false, &check_quoted/2) do
        { _, false } ->
          Macro.prewalk(quoted, &handle_fragment/1)
        { _, true } ->
          raise Eml.CompileError,
          type: :illegal_quoted,
          value: "It's not possible to use quoted expressions inside fragments"
      end
    else
      Macro.prewalk(quoted, &handle_template/1)
      |> Macro.prewalk(&temp_capture_rewrite_back/1)
    end
  end

  defp check_quoted({ :&, _, [_] } = arg, _quoted?) do
    { arg, true }
  end
  defp check_quoted({ :{}, _, _ } = arg, _quoted?) do
    { arg, true }
  end
  defp check_quoted({ :quote, _, _ } = arg, _quoted?) do
    { arg, true }
  end
  defp check_quoted(arg, quoted?) do
    { arg, quoted? }
  end

  defp handle_fragment({ :@, _, [{ name, _, atom }] } = arg) when is_atom(name) and is_atom(atom) do
    Macro.escape(EEx.Engine.handle_assign(arg))
  end
  defp handle_fragment(arg) do
    arg
  end

  defp handle_template({ :quote, meta, quoted }) do
    quoted = Macro.prewalk(quoted, &(temp_capture_rewrite(&1) |> handle_template_assign()))
    { :quote, meta, quoted }
  end
  defp handle_template({ :&, _, [call] }) do
    Macro.escape(Macro.prewalk(call, &handle_template_assign/1))
  end
  defp handle_template({ :@, _, [{ name, _, atom }]} = arg) when is_atom(name) and is_atom(atom) do
    Macro.escape(handle_template_assign(arg))
  end
  defp handle_template(arg) do
    arg
  end

  defp handle_template_assign({ :@, meta, [{ name, _, atom }] }) when is_atom(name) and is_atom(atom) do
    line = meta[:line] || 0
    quote line: line, do: Eml.Compiler.get_assign(var!(assigns), unquote(name))
  end
  defp handle_template_assign(arg) do
    arg
  end

  defp temp_capture_rewrite({ :&, meta, args }) do
    { :__temp__capture, meta, args }
  end
  defp temp_capture_rewrite(arg) do
    arg
  end

  defp temp_capture_rewrite_back({ :__temp__capture, meta, args }) do
    { :&, meta, args }
  end
  defp temp_capture_rewrite_back(arg) do
    arg
  end

  @doc false
  def get_assign(assigns, key) do
    case Dict.get(assigns, key) do
      { :safe, _ } = value ->
        value
      value when is_tuple(value) ->
        raise Eml.CompileError,
        type: :illegal_quoted,
        value: "It's not possible to pass quoted expressions to templates, components and Eml.render/3"
      value ->
        value
    end
  end
end
