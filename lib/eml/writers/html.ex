defmodule Eml.Writers.Html do
  @behaviour Eml.Writer

  use Eml.Markup.Record
  use Eml.Template.Record
  alias Eml.Markup
  alias Eml.Template
  alias Eml.Parameter, as: Param

  defrecord  Opts, indent: 2, quote: :single, escape: true, output: :string, pretty: true

  defrecordp :state, type: :content, chunks: [], params: [], pos: :inline
  
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
  
  defmacrop _s(type, chunks, params, pos) do
    quote do: state(type: unquote(type), chunks: unquote(chunks), params: unquote(params), pos: unquote(pos))
  end

  # API

  def write(templ() = t, opts) do
    new  = Keyword.get(opts, :bindings, [])
    opts = Opts.new(opts)
    t    = Template.bind(t, new)
    parse_templ(t, opts, state()) |> to_result(opts)
  end

  def write(eml, opts) do
    bindings = opts[:bindings]
    opts = Opts.new(opts)
    case { parse_eml(eml, opts, 0, state()) |> to_result(opts), bindings } do
      { { :ok, templ() = t }, b } when not nil?(b) ->
        t = Template.bind(t, b)
        parse_templ(t, opts, state()) |> to_result(opts)
      { res, _ } ->
        res
    end
  end

  # Eml parsing

  defp parse_eml(m(tag: tag, id: id, class: class, attrs: attrs, content: content),
                Opts[indent: iwidth, pretty: pretty] = opts, ilevel,
                _s(type, chunks, params)) do
    type  = chunk_type(:markup, type)
    attrs = Markup.maybe_include(attrs, [id: id, class: class])

    if content == [] do
      chunks = chunks
               |> newline(pretty)
               |> doctype_or_indent(tag, iwidth, ilevel, pretty)
               |> empty_tag_open(tag)
      _s(type, chunks, params) = parse_attrs(attrs, opts, _s(type, chunks, params))
      chunks = empty_tag_close(chunks)
      _s(type, chunks, params, :block)
    else
      chunks = chunks
               |> newline(pretty)
               |> doctype_or_indent(tag, iwidth, ilevel, pretty)
               |> start_tag_open(tag)
      _s(type, chunks, params) = parse_attrs(attrs, opts, _s(type, chunks, params))
      chunks = start_tag_close(chunks)
      _s(type, chunks, params, pos) = parse_eml(content, opts, ilevel + 1, _s(type, chunks, params))
      chunks = chunks
               |> newline(pos, pretty)
               |> indent(iwidth, ilevel, pos, pretty)
               |> end_tag(tag)
      _s(type, chunks, params, :block)
    end
  end

  defp parse_eml(list, opts, ilevel, s) when is_list(list) do
    Enum.reduce(list, s, fn eml, s ->
      parse_eml(eml, opts, ilevel, s)
    end)
  end

  defp parse_eml(param, _opts, ilevel, _s(chunks, params))
  when is_record(param, Param) do
    param = Param.ilevel(param, ilevel)
    _s(:templ, [param | chunks], add_param(params, param))
  end

  # Consume template chunks and params and become a template itself
  defp parse_eml(templ(chunks: tchunks, params: tparams), _opts, ilevel, _s(chunks, params)) do
    tchunks = Enum.reduce(tchunks, [], fn c, acc -> 
      if is_record(c, Param),
        do: [Param.ilevel(c, ilevel + Param.ilevel(c)) | acc],
      else: [c | acc]
    end)
    _s(:templ, tchunks ++ chunks, merge_params(params, tparams))
  end

  defp parse_eml(data, opts, _ilevel, s) do
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

  defp parse_attrs([{ k, param } | rest], opts, _s(chunks, params))
  when is_record(param, Param) do
    field  = attr_field(k)
    chunks = param_attr(chunks, field, param, opts)
    s      = _s(:templ, chunks, add_param(params, param))
    parse_attrs(rest, opts, s)
  end

  defp parse_attrs([{ k, v } | rest], opts, _s(type, chunks, params)) do
    type   = chunk_type(:attr, type)
    field  = attr_field(k)
    value  = attr_value(v, opts)
    chunks = if nil?(value), do: chunks, else: attr(chunks, field, value, opts)
    s      = _s(type, chunks, params)
    parse_attrs(rest, opts, s)
  end
  defp parse_attrs([], _, s), do: s

  # Template parsing

  defp parse_templ(templ(chunks: chunks, bindings: bindings), opts, s) do
    { _, _, s } = Enum.reduce(chunks, { bindings, opts, s }, &process_chunk/2)
    s
  end

  defp process_chunk(param, { bindings, opts, _s(chunks, params) = s })
  when is_record(param, Param) do
    { binding, bindings } = Template.pop(bindings, Param.id(param))
    if binding do
      {
       bindings,
       opts,
       parse_binding(binding, Param.type(param), opts, Param.ilevel(param), s)
      }
      else
        {
         bindings,
         opts,
         state(s, type: :templ, chunks: [param | chunks], params: add_param(params, param))
        }
    end
  end

  defp process_chunk(chunk, { bindings, opts, state(chunks: chunks) = s }) do
    { bindings, opts, state(s, chunks: [chunk | chunks]) }
  end

  defp parse_binding(binding, :content, opts, ilevel, s) do
    parse_eml(binding, opts, ilevel, s)
  end

  defp parse_binding(binding, :attr, opts, _ilevel, _s(chunks) = s) do
    state(s, type: :attr, chunks: [attr_value(binding, opts) | chunks])
  end

  # Markup generators

  defp empty_tag_open(chunks, tag), do: ["<#{tag}" | chunks]
  defp empty_tag_close(chunks),     do: ["/>" | chunks]
  defp start_tag_open(chunks, tag), do: ["<#{tag}" | chunks]
  defp start_tag_close(chunks),     do: [">" | chunks]
  defp end_tag(chunks, tag),        do: ["</#{tag}>" | chunks]

  defp newline(chunks, true),         do: ["\n" | chunks]
  defp newline(chunks, false),        do: chunks
  defp newline(chunks, :block, true), do: ["\n" | chunks]
  defp newline(chunks, _, _),         do: chunks

  defp doctype_or_indent(chunks, :html, _, _, _pretty), do: ["<!doctype html>\n" | chunks]
  defp doctype_or_indent(chunks, _, width, step, true), do: indent(chunks, width, step)
  defp doctype_or_indent(chunks, _, _, _, false),       do: chunks

  defp indent(chunks, _, 0),                      do: chunks
  defp indent(chunks, width, step),               do: [String.duplicate(" ", width * step) | chunks]
  defp indent(chunks, width, step, :block, true), do: indent(chunks, width, step)
  defp indent(chunks, _, _, _pos, _pretty),       do: chunks

  defp attr(chunks, field, value, Opts[quote: q]) do
    qchar = qchar(q)
    if nil?(value),
      do:   chunks,
      else: [" #{field}=#{qchar}#{value}#{qchar}" | chunks]
  end

  defp param_attr(chunks, field, param, Opts[quote: q]) do
    qchar = qchar(q)
    ["#{qchar}", param, " #{field}=#{qchar}" | chunks]
  end

  # Markup helpers

  defp qchar(:single), do: "'"
  defp qchar(:double), do: "\""
  defp qchar(_),       do: "'"

  defp maybe_escape(data, Opts[escape: true]) do
    escape(data)
  end

  defp maybe_escape(data, Opts[escape: false]) do
    data
  end

  defp escape(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp strip_newline(["\n" | data]), do: data
  defp strip_newline(data), do: data

  # Attribute markup helpers

  defp attr_field(field) do
    field = atom_to_binary(field)
    if String.starts_with?(field, "_"),
      do: "data-" <> String.lstrip(field, ?_),
    else: field
  end

  defp attr_value(v, opts) do
    v |> parse_attr_value() |> maybe_escape(opts)
  end

  defp parse_attr_value(list) when is_list(list) do
    Enum.join(list, " ")
  end

  defp parse_attr_value(v), do: v

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

  # Create final result, depending on state type and output option.

  defp to_result(state(type: :templ, chunks: chunks, params: params), _opts) do
    { :ok, templ(chunks: chunks |> consolidate_chunks(), params: params) }
  end

  defp to_result(state(chunks: chunks), Opts[output: :string]) do
    { :ok, chunks |> :lists.reverse() |> strip_newline() |> iolist_to_binary() }
  end

  defp to_result(state(chunks: chunks), Opts[output: :iolist]) do
    { :ok, chunks |> :lists.reverse() |> strip_newline() }
  end
end