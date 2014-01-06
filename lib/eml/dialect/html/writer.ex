defmodule Eml.Dialect.Html.Writer do
  use Eml.Markup.Record
  use Eml.Template.Record
  alias Eml.Markup
  alias Eml.Template
  alias Eml.Parameter, as: Param

  defrecord  Opts, indent: 2, quote: :single, escape: true, output: :string, pretty: false, mode: :render, force_templ: false

  defrecordp :state, type: :content, chunks: [], params: []
  
  # State handling shortcuts
  
  defmacrop _s(chunks) do
    quote do: state(chunks: unquote(chunks))
  end
  
  defmacrop _s(chunks, params) do
    quote do: state(chunks: unquote(chunks), params: unquote(params))
  end
  
  defmacrop _s(type, chunks, params) do
    quote do: state(type: unquote(type), chunks: unquote(chunks), params: unquote(params))
  end
  
  # API

  def write(templ() = t, opts) do
    new  = Keyword.get(opts, :bindings, [])
    opts = Keyword.put(opts, :mode, :compile)
    opts = Opts.new(opts)
    t    = Template.bind(t, new)
    parse_templ(t, opts, state()) |> to_result(opts)
  end

  def write(eml, opts) do
    bindings = opts[:bindings]
    force_templ? = opts[:force_templ]
    opts = case bindings do
             nil -> opts
             _   -> Keyword.put(opts, :mode, :compile)
           end
    opts = Opts.new(opts)
    type = if force_templ?, do: :templ, else: :content
    case { parse_eml(eml, opts, state(type: type)) |> to_result(opts), bindings } do
      { { :ok, templ() = t }, b } when not nil?(b) ->
        t = Template.bind(t, b)
        parse_templ(t, opts, state()) |> to_result(opts)
      { res, _ } ->
        res
    end
  end

  # Eml parsing

  defp parse_eml(m(tag: tag, id: id, class: class, attrs: attrs, content: content),
                 opts,
                 _s(type, chunks, params)) do
    type  = chunk_type(:markup, type)
    attrs = Markup.maybe_include(attrs, [id: id, class: class])

    if content == [] do
      chunks = chunks
               |> maybe_doctype(tag)
               |> empty_tag_open(tag)
      _s(type, chunks, params) = parse_attrs(attrs, opts, _s(type, chunks, params))
      chunks = empty_tag_close(chunks)
      _s(type, chunks, params)
    else
      chunks = chunks
               |> maybe_doctype(tag)
               |> start_tag_open(tag)
      _s(type, chunks, params) = parse_attrs(attrs, opts, _s(type, chunks, params))
      chunks = start_tag_close(chunks)
      _s(type, chunks, params) = parse_eml(content, opts, _s(type, chunks, params))
      chunks = end_tag(chunks, tag)
      _s(type, chunks, params)
    end
  end

  defp parse_eml(list, opts, s) when is_list(list) do
    Enum.reduce(list, s, fn eml, s ->
      parse_eml(eml, opts, s)
    end)
  end

  defp parse_eml(param, Opts[mode: :compile], _s(chunks, params))
  when is_record(param, Param) do
    _s(:templ, [param | chunks], add_param(params, param))
  end

  defp parse_eml(param, Opts[mode: :render], _s(type, chunks, params))
  when is_record(param, Param) do
    param = parse_param(param)
    _s(type, [param | chunks], params)
  end

  # If mode is compile, consume template chunks and params and become a template itself
  defp parse_eml(templ(chunks: tchunks, params: tparams), Opts[mode: :compile], _s(chunks, params)) do
    _s(:templ, :lists.reverse(tchunks) ++ chunks, merge_params(params, tparams))
  end

  # If mode is render, convert all parameters of the template to strings.
  defp parse_eml(templ(chunks: tchunks, params: tparams), Opts[mode: :render], _s(type, chunks, params)) do
    tchunks = Enum.reduce(tchunks, [], fn chunk, acc ->
      if Eml.type(chunk) === :parameter,
        do: [parse_param(chunk) | acc],
      else: [chunk | acc]
    end)
    _s(type, tchunks ++ chunks, merge_params(params, tparams))
  end

  defp parse_eml(data, opts, s) do
    parse_element(data, opts, s)
  end

  # Element parsing

  defp parse_element(content, opts, _s(type, chunks, params)) do
    _s(type, [maybe_escape(content, opts) | chunks], params)
  end

  # Attributes parsing

  defp parse_attrs(attrs, opts, s)

  defp parse_attrs([{ _, nil } | rest], opts, s) do
    parse_attrs(rest, opts, s)
  end

  defp parse_attrs([{ k, v } | rest], opts, _s(type, chunks, params)) do
    type   = chunk_type(:attr, type)
    field  = attr_field(k)
    value  = attr_value(v, opts)
    s = if Eml.type(value) == :parameter do
          chunks = attr(chunks, field, value, opts)
          _s(:templ, chunks, add_param(params, value))
        else
          chunks = if nil?(value), 
                     do: chunks,
                   else: attr(chunks, field, value, opts)
          _s(type, chunks, params)
        end
    parse_attrs(rest, opts, s)
  end
  
  defp parse_attrs([], _, s), do: s

  # Template parsing

  defp parse_templ(templ(chunks: chunks, bindings: bindings), opts, s) do
    { _, _, s } = Enum.reduce(chunks, { bindings, opts, s }, &process_chunk/2)
    s
  end

  defp process_chunk(param, { bindings, Opts[force_templ: force_templ?] = opts, _s(type, chunks, params)})
  when is_record(param, Param) do
    { binding, bindings } = Template.pop(bindings, Param.id(param))
    if binding do
      type = if force_templ?, do: :templ, else: type
      {
       bindings,
       opts,
       parse_binding(binding, Param.type(param), opts, _s(type, chunks, params))
      }
      else
        {
         bindings,
         opts,
         _s(:templ, [param | chunks], add_param(params, param))
        }
    end
  end

  defp process_chunk(chunk, { bindings, opts, state(chunks: chunks) = s }) do
    { bindings, opts, state(s, chunks: [chunk | chunks]) }
  end

  defp parse_binding(binding, :content, opts, s) do
    parse_eml(binding, opts, s)
  end

  defp parse_binding(binding, :attr, opts, _s(chunks) = s) do
    state(s, type: :attr, chunks: [attr_value(binding, opts) | chunks])
  end

  # Markup generators

  defp empty_tag_open(chunks, tag), do: ["<#{tag}" | chunks]
  defp empty_tag_close(chunks),     do: ["/>" | chunks]
  defp start_tag_open(chunks, tag), do: ["<#{tag}" | chunks]
  defp start_tag_close(chunks),     do: [">" | chunks]
  defp end_tag(chunks, tag),        do: ["</#{tag}>" | chunks]


  defp maybe_doctype(chunks, :html), do: ["<!doctype html>\n" | chunks]
  defp maybe_doctype(chunks, _),    do: chunks

  defp attr(chunks, field, param, Opts[quote: q]) do
    qchar = qchar(q)
    ["#{qchar}", param, " #{field}=#{qchar}" | chunks]
  end

  # Markup helpers

  defp qchar(:single), do: "'"
  defp qchar(:double), do: "\""
  defp qchar(_),       do: "'"

  defp maybe_escape(list, Opts[escape: true] = opts) when is_list(list) do
    lc data inlist list do
      maybe_escape(data, opts)
    end 
  end

  defp maybe_escape(data, _)
  when is_record(data, Param) do
    data
  end

  defp maybe_escape(data, Opts[escape: true]) do
    escape(data)
  end

  defp maybe_escape(data, Opts[escape: false]) do
    data
  end

  defp escape(s) when is_binary(s) do
    bc <<char>> inbits s, <<new::binary>> = escape_chars(char) do
      <<new::binary>>
    end
  end

  defp escape_chars(char) do
    case char do
      ?& -> <<"&amp;">>
      ?< -> <<"&lt;">>
      ?> -> <<"&gt;">>
      _  -> <<char>>
    end
  end


  defp parse_param(param) do
    "#param{#{Param.id(param)}}"
  end

  # Attribute markup helpers

  defp attr_field(field) do
    field = atom_to_binary(field)
    if String.starts_with?(field, "_"),
      do: "data-" <> String.lstrip(field, ?_),
    else: field
  end

  defp attr_value(v, opts) do
    parse_attr_value(v, opts) |> maybe_escape(opts)
  end

  defp parse_attr_value(list, Opts[mode: :compile])
  when is_list(list) do
    if Enum.any?(list, fn attr_v -> is_record(attr_v, Param) end),
      do: list,
    else: Enum.join(list, " ")
  end

  defp parse_attr_value(list, Opts[mode: :render])
  when is_list(list) do
    if Enum.any?(list, fn attr_v -> is_record(attr_v, Param) end) do
      lc attr_v inlist list do
        if is_record(attr_v, Param), 
          do: parse_param(attr_v),
        else: attr_v
      end
    else 
      Enum.join(list, " ")
    end
  end

  defp parse_attr_value(param, Opts[mode: mode])
  when is_record(param, Param) do
    case mode do
      :compile -> param
      :render  -> parse_param(param)
    end
  end

  defp parse_attr_value(v, _), do: v

  # Chunk helpers

  defp chunk_type(_, :templ), do: :templ
  defp chunk_type(type, _),   do: type

  # Template helpers

  defp add_param(params, param) do
    Keyword.update(params, Param.id(param), 1, &(&1 + 1))
  end

  defp merge_params(params1, params2) do
    Keyword.merge(params1, params2, fn _k, v1, v2 ->
      v1 + v2
    end)
  end

  # Concatenates chunks inbetween parameters for efficient template compiling.
  # It is feeded by the reverserd list of chunks,
  # so consolidate_chunks doesn't need to reverse its results.

  defp consolidate_chunks(chunks) do
    consolidate_chunks(chunks, "", [])
  end

  defp consolidate_chunks([param | chunks], str, acc)
  when is_record(param, Param) do
    consolidate_chunks(chunks, "", [param, str | acc])
  end

  defp consolidate_chunks([chunk | chunks], str, acc ) do
    consolidate_chunks(chunks, chunk <> str, acc )
  end

  defp consolidate_chunks([], <<"\n"::binary, str::binary>>, acc ) do
    [str | acc]
  end

  defp consolidate_chunks([], str, acc ) do
    [str | acc]
  end

  # pretty printing

  defp pretty_print(bin, width) do
    pretty_print(String.codepoints(bin), width, 0, true, []) 
  end

  defp pretty_print([">", "<", "/" | rest], width, level, _open?, acc) do
    level = level - 1
    pretty_print(rest, width, level, false, ["/", "<", String.duplicate(" ", width * level), "\n", ">"| acc])
  end
  defp pretty_print(["<", "/" | rest], width, level, _open?, acc) do
    pretty_print(rest, width, level, false, ["/", "<" | acc])
  end
  defp pretty_print(["/", ">" | rest], width, level, _open?, acc) do
    pretty_print(rest, width, level, false, [">", "/"  | acc])
  end
  defp pretty_print([">", "<" | rest], width, level, open?, acc) do
    level = if open?, do: level + 1, else: level
    pretty_print(rest, width, level, true, ["<", String.duplicate(" ", width * level), "\n", ">" | acc])
  end
  defp pretty_print([c | rest], width, level, open?, acc) do
    pretty_print(rest, width, level, open?, [c | acc])
  end
  defp pretty_print([], _width, _level, _open?, acc) do
    acc |> :lists.reverse() |> iolist_to_binary()
  end


  # Create final result, depending on state type and output option.

  defp to_result(state(type: :templ, chunks: chunks, params: params), _opts) do
    { :ok, templ(chunks: chunks |> consolidate_chunks(), params: params) }
  end

  defp to_result(state(chunks: chunks), Opts[output: :string, pretty: true, indent: width]) do
    { :ok, chunks |> :lists.reverse() |> iolist_to_binary() |> pretty_print(width)  }
  end

  defp to_result(state(chunks: chunks), Opts[output: :string]) do
    { :ok, chunks |> :lists.reverse() |> iolist_to_binary() }
  end

  defp to_result(state(chunks: chunks), Opts[output: :iolist]) do
    { :ok, chunks |> :lists.reverse() }
  end
end