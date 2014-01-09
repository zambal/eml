defmodule Eml.Language.Html.Writer do
  use Eml.Markup.Record
  use Eml.Template.Record
  alias Eml.Markup
  alias Eml.Template
  alias Eml.Parameter, as: Param

  defrecord  Opts, indent: 2,
                   quote: :single,
                   escape: true,
                   output: :string,
                   pretty: false,
                   mode: :render,
                   force_templ: false

  defrecordp :state, type: :content, chunks: [], params: [], bindings: []
    
  # API

  def write(templ() = t, opts) do
    new  = Keyword.get(opts, :bindings, [])
    opts = Keyword.put(opts, :mode, :compile)
           |> Opts.new()
    t = Template.bind(t, new)
    parse_templ(t, opts, state()) |> to_result(opts)
  end

  def write(eml, opts) do
    bindings = Keyword.get(opts, :bindings, [])
               |> read_bindings()
    type = if opts[:force_templ], do: :templ, else: :content
    opts = case bindings do
             [] -> opts
             _  -> Keyword.put(opts, :mode, :compile)
           end |> Opts.new()
    parse_eml(eml, opts, state(type: type, bindings: bindings)) |> to_result(opts)
  end

  # Eml parsing

  defp parse_eml(m(tag: tag, id: id, class: class, attrs: attrs, content: content),
                 opts, state(type: type, chunks: chunks) = s) do

    type  = chunk_type(:markup, type)
    attrs = Markup.maybe_include(attrs, [id: id, class: class])

    if content == [] do
      chunks = chunks
               |> maybe_doctype(tag)
               |> empty_tag_open(tag)
      s = state(chunks: chunks) = parse_attrs(attrs, opts, state(s, type: type, chunks: chunks))
      chunks = empty_tag_close(chunks)
      state(s, chunks: chunks)
    else
      chunks = chunks
               |> maybe_doctype(tag)
               |> start_tag_open(tag)
      s = state(chunks: chunks) = parse_attrs(attrs, opts, state(s, type: type, chunks: chunks))
      chunks = start_tag_close(chunks)
      s = state(chunks: chunks) = parse_eml(content, opts, state(s, chunks: chunks))
      chunks = end_tag(chunks, tag)
      state(s, chunks: chunks)
    end
  end

  defp parse_eml(list, opts, s) when is_list(list) do
    Enum.reduce(list, s, fn eml, s ->
      parse_eml(eml, opts, s)
    end)
  end

  defp parse_eml(param, Opts[mode: :compile] = opts, state(chunks: chunks, params: params, bindings: bindings) = s)
  when is_record(param, Param) do
    case Template.pop(bindings, Param.id(param)) do
      { nil, b }   -> state(type: :templ, chunks: [param | chunks], params: add_param(params, param), bindings: b)
      { value, b } -> parse_eml(value, opts, state(s, bindings: b))
    end
  end

  defp parse_eml(param, Opts[mode: :render], state(chunks: chunks, params: params) = s)
  when is_record(param, Param) do
    param = parse_param(param)
    state(s, chunks: [param | chunks], params: params)
  end

  defp parse_eml(templ() = t, Opts[mode: :compile] = opts, state(chunks: chunks, params: params, bindings: bindings) = s) do
    cond do
      # If bound, render template and add it to chunks.
      Template.bound?(t) ->
        { :ok, bin } = parse_templ(t, opts, state())
        state(s, chunks: [bin | chunks])
      # If not bound, but there are bindings left in the parse state,
      # try to render the template with them.
      # If still a template, make a new parse state of type template
      # and add all chunks, params and leftover bindings to it.
      # If rendered, add to chunks.
      bindings !== [] ->
        t = Template.bind(t, bindings)
        case parse_templ(t, opts, state()) do
          state(type: :templ, chunks: tchunks, params: tparams, bindings: tbindings) ->
            state(type: :templ, chunks: tchunks ++ chunks, params: merge_params(params, tparams), bindings: tbindings)
          state(chunks: rchunks, bindings: rbindings) ->
            state(s, chunks: rchunks ++ chunks, bindings: rbindings)
        end
      # otherwise make a new parse state of type template
      # and add the all chunks and params to it.
      true ->
        templ(chunks: tchunks, params: tparams) = t
        state(type: :templ, chunks: :lists.reverse(tchunks) ++ chunks, params: merge_params(params, tparams))
    end
  end

  # If mode is render, convert all parameters of the template to strings.
  defp parse_eml(templ(chunks: tchunks, params: tparams), Opts[mode: :render], state(chunks: chunks, params: params) = s) do
    tchunks = Enum.reduce(tchunks, [], fn chunk, acc ->
      if Eml.type(chunk) === :parameter,
        do: [parse_param(chunk) | acc],
      else: [chunk | acc]
    end)
    state(s, chunks: tchunks ++ chunks, params: merge_params(params, tparams))
  end

  defp parse_eml(data, opts, state(chunks: chunks) = s) do
    state(s, chunks: [maybe_escape(data, opts) | chunks])
  end

  # Attributes parsing

  defp parse_attrs(attrs, opts, s)

  defp parse_attrs([{ _, nil } | rest], opts, s) do
    parse_attrs(rest, opts, s)
  end

  defp parse_attrs([{ k, v } | rest], opts, state(type: type) = s) do
    type = chunk_type(:attr, type)
    s    = parse_attr(k, v, opts, state(s, type: type)) 
    parse_attrs(rest, opts, s)
  end
  
  defp parse_attrs([], _, s), do: s

  defp parse_attr(_, nil, _, s), do: s
  defp parse_attr(field, value, Opts[quote: q] = opts, state(chunks: chunks) = s) do
    qchar  = qchar(q)
    field  = attr_field(field)
    chunks = [" #{field}=#{qchar}" | chunks]
    s      = state(chunks: chunks) = parse_attr_value(value, opts, state(s, chunks: chunks))
    chunks = ["#{qchar}" | chunks]
    state(s, chunks: chunks)
  end

  defp parse_attr_value(list, opts, state(chunks: chunks, params: params, bindings: bindings) = s) when is_list(list) do
    attr_s = Enum.reduce(list, state(type: :attr, bindings: bindings), fn value, s  ->
      parse_attr_value(value, opts, s)
    end)
    case attr_s do
      state(type: :templ, chunks: tchunks, params: tparams, bindings: tbindings) ->
        tchunks = insert_whitespace(tchunks)
        state(type: :templ, chunks: tchunks ++ chunks, params: merge_params(params, tparams), bindings: tbindings)
      state(chunks: rchunks, bindings: rbindings) ->
        rchunks = insert_whitespace(rchunks)
        state(s, chunks: rchunks ++ chunks, bindings: rbindings)
    end
  end

  defp parse_attr_value(param, Opts[mode: mode] = opts, state(chunks: chunks, params: params, bindings: bindings) = s)
  when is_record(param, Param) do
    case mode do
      :compile ->
        case Template.pop(bindings, Param.id(param)) do
          { nil, b }   -> state(type: :templ, chunks: [param | chunks], params: add_param(params, param), bindings: b)
          { value, b } -> parse_attr_value(value, opts, state(s, bindings: b))
        end
      :render  ->
        state(s, chunks: [parse_param(param) | chunks])
    end
  end

  defp parse_attr_value(value, opts, state(chunks: chunks) = s) do
    state(s, chunks: [maybe_escape(value, opts) | chunks])
  end

  # Template parsing

  defp parse_templ(templ(chunks: chunks, bindings: bindings), Opts[force_templ: force_templ?] = opts, state(type: type) = s) do
    type = if force_templ?, do: :templ, else: type
    process_chunk = fn
      param, st when is_record(param, Param) ->
        expand_param(param, Param.type(param), opts, st)
      chunk, state(chunks: chunks) = st ->
        state(st, chunks: [chunk | chunks])
    end
    Enum.reduce(chunks, state(s, type: type, bindings: bindings), process_chunk)
  end

  defp expand_param(param, :content, opts, s) do
    parse_eml(param, opts, s)
  end

  defp expand_param(param, :attr, opts, s) do
    parse_attr_value(param, opts, s)
  end

  # Markup generators

  defp empty_tag_open(chunks, tag), do: ["<#{tag}" | chunks]
  defp empty_tag_close(chunks),     do: ["/>" | chunks]
  defp start_tag_open(chunks, tag), do: ["<#{tag}" | chunks]
  defp start_tag_close(chunks),     do: [">" | chunks]
  defp end_tag(chunks, tag),        do: ["</#{tag}>" | chunks]


  defp maybe_doctype(chunks, :html), do: ["<!doctype html>\n" | chunks]
  defp maybe_doctype(chunks, _),     do: chunks


  # Markup helpers

  defp parse_param(param) do
    "#param{#{Param.id(param)}}"  
  end

  defp maybe_escape(data, Opts[escape: true]) do
    escape(data)
  end

  defp maybe_escape(data, Opts[escape: false]) do
    data
  end

  defp escape(s) do
    :binary.replace(s, "&", "&amp;", [:global])
    |> :binary.replace("<", "&lt;", [:global])
    |> :binary.replace(">", "&gt;", [:global])
  end

  # Attribute markup helpers

  defp qchar(:single), do: "'"
  defp qchar(:double), do: "\""
  defp qchar(_),       do: "'"

  defp attr_field(field) do
    field = atom_to_binary(field)
    if String.starts_with?(field, "_"),
      do: "data-" <> String.lstrip(field, ?_),
    else: field
  end

  # Insert a space between attribute values
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
    :lists.reverse(acc)
  end

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

  # Bindings helpers

  defp read_bindings(bindings) do
    Enum.map(bindings, fn { k, v } ->
      v = (if is_list(v), do: v, else: [v])
          |> Enum.map(fn v -> Eml.read(v, Eml.Language.Native) end)
      { k, v }
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

  defp consolidate_chunks([], str, [h | t]) do
    if is_binary(h) do
      [h <> str | t]
    else
      [str, h | t]
    end
  end

  defp consolidate_chunks([], str, _) do
    str
  end

  # pretty printing

  defp pretty_print(bin, width) do
    pretty_print(bin, width, 0, true, <<>>) 
  end

  defp pretty_print(<<"></", rest::binary>>, width, level, _open?, acc) do
    level = level - 1
    b = ">\n" <> String.duplicate(" ", width * level) <> "</"
    pretty_print(rest, width, level, false, <<acc::binary, b::binary>>)
  end
  defp pretty_print(<<"</", rest::binary>>, width, level, _open?, acc) do
    pretty_print(rest, width, level, false, <<acc::binary, "</">>)
  end
  defp pretty_print(<<"/>", rest::binary>>, width, level, _open?, acc) do
    pretty_print(rest, width, level, false, <<acc::binary, "/>">>)
  end
  defp pretty_print(<<"><", rest::binary>>, width, level, open?, acc) do
    level = if open?, do: level + 1, else: level
    b = ">\n" <> String.duplicate(" ", width * level) <> "<"
    pretty_print(rest, width, level, true, <<acc::binary, b::binary>>)
  end
  defp pretty_print(<<c, rest::binary>>, width, level, open?, acc) do
    pretty_print(rest, width, level, open?, <<acc::binary, c>>)
  end
  defp pretty_print(<<>>, _width, _level, _open?, acc) do
    acc
  end


  # Create final result, depending on state type and output option.

  defp to_result(state(type: :templ, chunks: chunks, params: params, bindings: bindings), _opts) do
    { :ok, templ(chunks: chunks |> consolidate_chunks(), params: params, bindings: bindings) }
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