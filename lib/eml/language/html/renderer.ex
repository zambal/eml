defmodule Eml.Language.Html.Renderer do
  @moduledoc false

  alias Eml.Element
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
              bindings: [],
              current_tag: nil}

  defp state(fields), do: Dict.merge(@defstate, fields)

  # API

  def render(eml, opts) do
    { bindings, opts } = Keyword.pop(opts, :bindings, [])
    bindings = parse_bindings(bindings)
    opts = Dict.merge(@defopts, opts)
    type = if opts.mode == :compile, do: :templ, else: :content
    parse_eml(eml, opts, %{@defstate| type: type, bindings: bindings}) |> to_result(opts)
  end

  # Eml parsing

  defp parse_eml(%Element{tag: tag, attrs: attrs, content: content},
                 opts, %{type: type, chunks: chunks} = s) do

    type  = chunk_type(:element, type)

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

  defp parse_eml(%Parameter{} = param, %{render_params: false} = opts, %{chunks: chunks, bindings: bindings} = s) do
    case bindings[param.id] do
      nil   -> %{s| type: :templ, chunks: [param | chunks]}
      value -> parse_eml(value, opts, s)
    end
  end

  defp parse_eml(%Parameter{} = param, %{render_params: true}, %{chunks: chunks} = s) do
    param = parse_param(param)
    %{s| chunks: [param | chunks]}
  end

  defp parse_eml(%Template{} = t, %{render_params: false} = opts, %{chunks: chunks, bindings: bindings} = s) do
    # If bound, render template and add it to chunks.
    if Template.bound?(t) do
        %{chunks: rchunks} = parse_templ(t, opts, @defstate)
        %{s| chunks: rchunks ++ chunks}
      # If not bound, but there are bindings left in the parse state,
      # try to render the template with them.
      # If still a template, make a new parse state of type template
      # and add all chunks and leftover bindings to it.
      # If rendered, add to chunks.
    else
        t = Template.bind(t, bindings)
        case parse_templ(t, opts, @defstate) do
          %{type: :templ, chunks: tchunks} ->
            %{s| type: :templ, chunks: tchunks ++ chunks}
          %{chunks: rchunks} ->
            %{s| chunks: rchunks ++ chunks}
        end
    end
  end

  # If mode is render, convert all parameters of the template to strings.
  defp parse_eml(%Template{chunks: tchunks}, %{render_params: true}, %{chunks: chunks} = s) do
    tchunks = Enum.reduce(tchunks, [], fn chunk, acc ->
      if Eml.type(chunk) === :parameter,
        do: [parse_param(chunk) | acc],
      else: [chunk | acc]
    end)
    %{s| chunks: tchunks ++ chunks}
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
    %{chunks: chunks} = s = parse_attr_value(value, opts, %{s| chunks: chunks})
    chunks = ["#{qchar}" | chunks]
    %{s| chunks: chunks}
  end

  defp parse_attr_value(list, opts, %{chunks: chunks, bindings: bindings} = s) when is_list(list) do
    attr_s = Enum.reduce(list, state(type: :attr, bindings: bindings), fn value, s  ->
      parse_attr_value(value, opts, s)
    end)
    case attr_s do
      %{type: :templ, chunks: tchunks} ->
        tchunks = insert_whitespace(tchunks)
        %{s| type: :templ, chunks: tchunks ++ chunks}
      %{chunks: rchunks} ->
        rchunks = insert_whitespace(rchunks)
        %{s| chunks: rchunks ++ chunks}
    end
  end

  defp parse_attr_value(%Parameter{} = param, %{render_params: render_params} = opts, %{chunks: chunks, bindings: bindings} = s) do
    if render_params do
      %{s| chunks: [parse_param(param) | chunks]}
    else
      case bindings[param.id] do
        nil   -> %{s| type: :templ, chunks: [param | chunks]}
        value -> parse_attr_value(value, opts, s)
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

  # Element generators

  defp start_tag_open(chunks, tag), do: ["<#{tag}" | chunks]
  defp start_tag_close(chunks),     do: [">" | chunks]
  defp void_tag_close(chunks),     do: ["/>" | chunks]
  defp end_tag(chunks, tag),        do: ["</#{tag}>" | chunks]


  defp maybe_doctype(chunks, :html), do: ["<!doctype html>\n" | chunks]
  defp maybe_doctype(chunks, _),     do: chunks


  # Element helpers

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

  # Attribute element helpers

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

  # Bindings helpers

  defp parse_bindings(bindings) do
    Enum.map(bindings, fn { k, v } ->
      v = (if is_list(v), do: v, else: [v])
          |> Enum.map(fn v -> Eml.parse!(v, Eml.Language.Native) end)
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

  defp to_result(%{type: :templ, chunks: chunks}, opts) do
    t = %Template{chunks: chunks |> consolidate_chunks()}
    if opts.mode == :compile do
      { :ok, t }
    else
      { :error, { :unbound_params, Template.unbound(t) } }
    end
  end

  defp to_result(%{chunks: chunks}, %{output: :string}) do
    { :ok, chunks |> :lists.reverse() |> IO.iodata_to_binary() }
  end

  defp to_result(%{chunks: chunks}, %{output: :iolist}) do
    { :ok, chunks |> :lists.reverse() }
  end
end
