defmodule Eml.Language.Html.Writer do
  alias Eml.Markup
  alias Eml.Template
  alias Eml.Parameter

  @defopts %{indent: 2,
             quote: :single,
             escape: true,
             output: :string,
             mode: :render,
             render_params: false}

  @defstate %{type: :content,
              chunks: [],
              params: [],
              bindings: [],
              current_tag: nil}

  defp state(fields), do: Dict.merge(@defstate, fields)

  # API

  def write(eml, opts) do
    { bindings, opts } = Keyword.pop(opts, :bindings, [])
    bindings = read_bindings(bindings)
    opts = Dict.merge(@defopts, opts)
    type = if opts.mode == :compile, do: :templ, else: :content
    parse_eml(eml, opts, %{@defstate| type: type, bindings: bindings}) |> to_result(opts)
  end

  # Eml parsing

  defp parse_eml(%Markup{tag: tag, attrs: attrs, content: content},
                 opts, %{type: type, chunks: chunks} = s) do

    type  = chunk_type(:markup, type)

    chunks = chunks
             |> maybe_doctype(tag)
             |> start_tag_open(tag)
    s = %{chunks: chunks} = parse_attrs(attrs, opts, %{s| type: type, chunks: chunks, current_tag: tag})
    if is_void_element?(tag) do
      chunks = void_tag_close(chunks)
    else
      chunks = start_tag_close(chunks)
      s = %{chunks: chunks} = parse_eml(content, opts, %{s| chunks: chunks})
      chunks = end_tag(chunks, tag)
    end
    %{s| chunks: chunks}
  end

  defp parse_eml(list, opts, s) when is_list(list) do
    Enum.reduce(list, s, fn eml, s ->
      parse_eml(eml, opts, s)
    end)
  end

  defp parse_eml(%Parameter{} = param, %{render_params: false} = opts, %{chunks: chunks, params: params, bindings: bindings} = s) do
    case Template.pop(bindings, param.id) do
      { nil, b }   -> %{s| type: :templ, chunks: [param | chunks], params: add_param(params, param), bindings: b}
      { value, b } -> parse_eml(value, opts, %{s| bindings: b})
    end
  end

  defp parse_eml(%Parameter{} = param, %{render_params: true}, %{chunks: chunks, params: params} = s) do
    param = parse_param(param)
    %{s| chunks: [param | chunks], params: params}
  end

  defp parse_eml(%Template{} = t, %{render_params: false} = opts, %{chunks: chunks, params: params, bindings: bindings} = s) do
    cond do
      # If bound, render template and add it to chunks.
      Template.bound?(t) ->
        %{chunks: rchunks, bindings: rbindings} = parse_templ(t, opts, @defstate)
        %{s| chunks: rchunks ++ chunks, bindings: rbindings ++ bindings}
      # If not bound, but there are bindings left in the parse state,
      # try to render the template with them.
      # If still a template, make a new parse state of type template
      # and add all chunks, params and leftover bindings to it.
      # If rendered, add to chunks.
      bindings !== [] ->
        t = Template.bind(t, bindings)
        case parse_templ(t, opts, @defstate) do
          %{type: :templ, chunks: tchunks, params: tparams, bindings: tbindings} ->
            %{s| type: :templ, chunks: tchunks ++ chunks, params: merge_params(params, tparams), bindings: tbindings}
          %{chunks: rchunks, bindings: rbindings} ->
            %{s| chunks: rchunks ++ chunks, bindings: rbindings}
        end
      # otherwise make a new parse state of type template
      # and add the all chunks and params to it.
      true ->
        %Template{chunks: tchunks, params: tparams} = t
        state(type: :templ, chunks: :lists.reverse(tchunks) ++ chunks, params: merge_params(params, tparams))
    end
  end

  # If mode is render, convert all parameters of the template to strings.
  defp parse_eml(%Template{chunks: tchunks, params: tparams}, %{render_params: true}, %{chunks: chunks, params: params} = s) do
    tchunks = Enum.reduce(tchunks, [], fn chunk, acc ->
      if Eml.type(chunk) === :parameter,
        do: [parse_param(chunk) | acc],
      else: [chunk | acc]
    end)
    %{s| chunks: tchunks ++ chunks, params: merge_params(params, tparams)}
  end

  defp parse_eml(data, opts, %{chunks: chunks, current_tag: tag} = s) do
    %{s| chunks: [maybe_escape(data, tag, opts) | chunks]}
  end

  # Attributes parsing

  defp parse_attrs(attrs, opts, s)

  defp parse_attrs(attrs, opts, s) when is_map(attrs) do
    parse_attrs(Enum.to_list(attrs), opts, s)
  end

  defp parse_attrs([{ _, nil } | rest], opts, s) do
    parse_attrs(rest, opts, s)
  end

  defp parse_attrs([{ k, v } | rest], opts, %{type: type} = s) do
    type = chunk_type(:attr, type)
    s    = parse_attr(k, v, opts, %{s| type: type})
    parse_attrs(rest, opts, s)
  end

  defp parse_attrs([], _, s), do: s

  defp parse_attr(_, nil, _, s), do: s
  defp parse_attr(field, value, %{quote: q} = opts, %{chunks: chunks} = s) do
    qchar  = qchar(q)
    field  = attr_field(field)
    chunks = [" #{field}=#{qchar}" | chunks]
    s      = %{chunks: chunks} = parse_attr_value(value, opts, %{s| chunks: chunks})
    chunks = ["#{qchar}" | chunks]
    %{s| chunks: chunks}
  end

  defp parse_attr_value(list, opts, %{chunks: chunks, params: params, bindings: bindings} = s) when is_list(list) do
    attr_s = Enum.reduce(list, state(type: :attr, bindings: bindings), fn value, s  ->
      parse_attr_value(value, opts, s)
    end)
    case attr_s do
      %{type: :templ, chunks: tchunks, params: tparams, bindings: tbindings} ->
        tchunks = insert_whitespace(tchunks)
        %{type: :templ, chunks: tchunks ++ chunks, params: merge_params(params, tparams), bindings: tbindings}
      %{chunks: rchunks, bindings: rbindings} ->
        rchunks = insert_whitespace(rchunks)
        %{s| chunks: rchunks ++ chunks, bindings: rbindings}
    end
  end

  defp parse_attr_value(%Parameter{} = param, %{render_params: render_params} = opts, %{chunks: chunks, params: params, bindings: bindings} = s) do
    if render_params do
      %{s| chunks: [parse_param(param) | chunks]}
    else
      case Template.pop(bindings, param.id) do
        { nil, b }   -> %{s| type: :templ, chunks: [param | chunks], params: add_param(params, param), bindings: b}
        { value, b } -> parse_attr_value(value, opts, %{s| bindings: b})
      end
    end
  end

  defp parse_attr_value(value, opts, %{chunks: chunks} = s) do
    %{s| chunks: [maybe_escape(value, opts) | chunks]}
  end

  # Template parsing

  defp parse_templ(%Template{chunks: chunks, bindings: bindings}, %{mode: mode} = opts, %{type: type} = s) do
    type = if mode == :compile, do: :templ, else: type
    process_chunk = fn
      %Parameter{} = param, st ->
        expand_param(param, param.type, opts, st)
      chunk, %{chunks: chunks} = st ->
        %{st| chunks: [chunk | chunks]}
    end
    Enum.reduce(chunks, %{s| type: type, bindings: bindings}, process_chunk)
  end

  defp expand_param(param, :content, opts, s) do
    parse_eml(param, opts, s)
  end

  defp expand_param(param, :attr, opts, s) do
    parse_attr_value(param, opts, s)
  end

  # Markup generators

  defp start_tag_open(chunks, tag), do: ["<#{tag}" | chunks]
  defp start_tag_close(chunks),     do: [">" | chunks]
  defp void_tag_close(chunks),     do: ["/>" | chunks]
  defp end_tag(chunks, tag),        do: ["</#{tag}>" | chunks]


  defp maybe_doctype(chunks, :html), do: ["<!doctype html>\n" | chunks]
  defp maybe_doctype(chunks, _),     do: chunks


  # Markup helpers

  defp parse_param(param) do
    "#param{#{param.id}}"
  end

  defp maybe_escape(data, tag \\ nil, opts)
  defp maybe_escape(data, tag, %{escape: true})
  when not tag in [:script, :style] do
    escape(data)
  end
  defp maybe_escape(data, _tag, _opts) do
    data
  end

  defp escape(s) do
    :binary.replace(s, "&", "&amp;", [:global])
    |> :binary.replace("<", "&lt;", [:global])
    |> :binary.replace(">", "&gt;", [:global])
  end

  defp is_void_element?(tag) do
    tag in [:area, :base, :br, :col, :embed, :hr, :img, :input, :keygen, :link, :meta, :param, :source, :track, :wbr]
  end

  # Attribute markup helpers

  defp qchar(:single), do: "'"
  defp qchar(:double), do: "\""
  defp qchar(_),       do: "'"

  defp attr_field(field) do
    field = Atom.to_string(field)
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
    Keyword.update(params, param.id, 1, &(&1 + 1))
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

  defp consolidate_chunks(chunks), do: consolidate_chunks(chunks, [])

  defp consolidate_chunks([], acc),             do: acc
  defp consolidate_chunks([chunk | rest], []),  do: consolidate_chunks(rest, [chunk])
  defp consolidate_chunks([chunk | rest], [h | t])
  when is_binary(chunk) and is_binary(h),       do: consolidate_chunks(rest, [chunk <> h | t])
  defp consolidate_chunks([chunk | rest], acc), do: consolidate_chunks(rest, [chunk | acc])

  # Create final result, depending on state type and output option.

  defp to_result(%{type: :templ, chunks: chunks, params: params, bindings: bindings}, opts) do
    if opts.mode == :compile do
      { :ok, %Template{chunks: chunks |> consolidate_chunks(), params: params, bindings: bindings} }
    else
      { :error, { :unbound_params, params } }
    end
  end

  defp to_result(%{chunks: chunks}, %{output: :string}) do
    { :ok, chunks |> :lists.reverse() |> IO.iodata_to_binary() }
  end

  defp to_result(%{chunks: chunks}, %{output: :iolist}) do
    { :ok, chunks |> :lists.reverse() }
  end
end
