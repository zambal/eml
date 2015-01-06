defmodule Eml.Markup do
  alias __MODULE__, as: M

  defstruct tag: :div, content: [], attrs: %{}

  @type data       :: Eml.data
  @type content    :: Eml.content

  @type attr_field :: atom
  @type attr_value :: binary | list(binary) | nil
  @type attrs      :: list({ attr_field, attr_value })
                    | %{ attr_field => attr_value }
  @type fields :: map

  @type t :: %M{tag: atom, content: content, attrs: map}

  @default_lang Eml.Language.Native

  @spec new() :: t
  def new(), do: %M{}

  @spec new(atom, fields, data, Eml.lang) :: t
  def new(tag, attrs \\ %{}, content \\ [], lang \\ @default_lang) when is_atom(tag) and (is_map(attrs) or is_list(attrs)) do
    attrs   = to_attrs(attrs)
    content = Eml.read!(content, lang)
    %M{tag: tag, attrs: attrs, content: content}
  end

  @spec tag(t) :: atom
  def tag(%M{tag: tag}), do: tag

  @spec tag(t, atom) :: t
  def tag(%M{} = markup, tag)
  when is_atom(tag), do: %{markup| "__tag__": tag}

  @spec id(t) :: attr_value
  def id(%M{attrs: attrs}), do: attrs[:id]

  @spec id(t, attr_value) :: t
  def id(%M{attrs: attrs} = markup, id),
  do: %M{markup| attrs: Map.put(attrs, :id, to_attr_value(id))}

  @spec class(t) :: attr_value
  def class(%M{attrs: attrs}), do: attrs[:class]

  @spec class(t, attr_value) :: t
  def class(%M{attrs: attrs} = markup, class),
  do: %M{markup| attrs: Map.put(attrs, :class, to_attr_value(class))}

  @spec content(t) :: content
  def content(%M{content: content}), do: content

  @spec content(t, data, Eml.lang) :: t
  def content(%M{} = markup, data, lang \\ @default_lang) do
    %M{markup| content: Eml.read!(data, lang)}
  end

  @spec add(t, data, Keyword.t) :: t
  def add(%M{content: current} = markup, data, opts \\ []) do
    at      = opts[:at] || :end
    lang  = opts[:lang] || @default_lang
    content = Eml.read!(data, current, at, lang)
    %M{markup| content: content}
  end

  @spec update(t, (Eml.element -> data), Eml.lang) :: t
  def update(%M{content: content} = markup, fun, lang \\ @default_lang) do
    content = for element <- content, data = fun.(element) do
      Eml.Readable.read(data, lang)
    end
    %M{markup| content: content}
  end

  @spec remove(t, Eml.element | content) :: t
  def remove(%M{content: content} = markup, to_remove) do
    to_remove = if is_list(to_remove), do: to_remove, else: [to_remove]
    content = for element <- content, not element in to_remove do
      element
    end
    %M{markup| content: content}
  end

  @spec attrs(t) :: attrs
  def attrs(%M{attrs: attrs}), do: attrs

  @spec attrs(t, attrs) :: t
  def attrs(%M{attrs: current} = markup, attrs) when is_map(attrs) or is_list(attrs) do
    %M{markup| attrs: Map.merge(current, to_attrs(attrs))}
  end

  @spec attr(t, atom) :: attr_value
  def attr(%M{attrs: attrs}, field) when is_atom(field) do
    attrs[field]
  end

  @spec attr(t, atom, attr_value) :: t
  def attr(%M{attrs: attrs} = markup, field, value) when is_atom(field) do
    %M{markup| attrs: Map.put(attrs, field, to_attr_value(value))}
  end

  @spec insert_attr_value(t, atom, attr_value) :: t
  def insert_attr_value(%M{attrs: attrs} = markup, field, value) when is_atom(field) do
    %M{markup| attrs: Map.update(attrs, field, to_attr_value(value), &insert_attr_value(&1, value))}
  end

  defp insert_attr_value(old, new) do
    old = ensure_list(old)
    new = ensure_list(new)
    for v <- new do
      to_attr_value(v)
    end ++ old
  end

  @spec remove_attr(t, atom) :: t
  def remove_attr(%M{attrs: attrs} = markup, field) do
    %M{markup| attrs: Map.delete(attrs, field)}
  end

  @spec has?(t, Keyword.t) :: boolean
  def has?(%M{} = markup, opts) when is_list(opts) do
    { tag, opts }      = Keyword.pop(opts, :tag, :any)
    { id, opts }       = Keyword.pop(opts, :id, :any)
    { class, opts }    = Keyword.pop(opts, :class, :any)
    { content, attrs } = Keyword.pop(opts, :content)
    content            = Eml.read!(content, @default_lang)
    content            = if content == [], do: :any, else: content

    has_tag?(markup, tag)         and
    has_id?(markup, id)           and
    has_class?(markup, class)     and
    has_content?(markup, content) and
    has_attrs?(markup, attrs)
  end
  def has?(_non_markup, _opts), do: false

  defp has_tag?(_, :any), do: true
  defp has_tag?(%M{tag: etag}, tag), do: tag === etag

  defp has_id?(_, :any), do: true
  defp has_id?(%M{attrs: %{id: eid}}, id), do: id === eid
  defp has_id?(_, _), do: false

  defp has_class?(_, :any), do: true
  defp has_class?(%M{attrs: %{class: eclass}}, classes) when is_list(classes) do
    Enum.all?(classes, &class?(&1, eclass))
  end
  defp has_class?(%M{attrs: %{class: eclass}}, class), do: class?(class, eclass)
  defp has_class?(_, _), do: false

  defp has_content?(_, :any), do: true
  defp has_content?(%M{content: econtent}, content) do
    Enum.all?(content, &Kernel.in(&1, econtent))
  end

  defp has_attrs?(_, []), do: true
  defp has_attrs?(markup, attrs) do
    eattrs = attrs(markup)
    Enum.all?(attrs, fn attr ->
      attr?(attr, eattrs)
    end)
  end

  defp attr?({ field, value }, attrs) do
    Enum.any?(attrs, fn { f, v } ->
      field === f and (value === :any or value === v)
    end)
  end

  def match?(_, tag, id \\ :any, class \\ :any)

  def match?(_, :any, :any, :any),
  do: true

  def match?(%M{tag: etag}, tag, :any, :any),
  do: tag === etag

  def match?(%M{attrs: %{id: eid}}, :any, id, :any),
  do: id === eid

  def match?(%M{attrs: %{class: eclass}}, :any, :any, class),
  do: class?(class, eclass)

  def match?(%M{tag: etag, attrs: %{id: eid}}, tag, id, :any),
  do: tag === etag and id === eid

  def match?(%M{tag: etag, attrs: %{class: eclass}}, tag, :any, class),
  do: tag === etag and class?(class, eclass)

  def match?(%M{ attrs: %{id: eid, class: eclass}}, :any, id, class),
  do: id === eid and class?(class, eclass)

  def match?(%M{tag: etag, attrs: %{id: eid, class: eclass}}, tag, id, class),
  do: tag === etag and id === eid and class?(class, eclass)

  def match?(_, _, _, _),
  do: false

  defp class?(class, classes) do
    if is_list(classes),
      do:   class in classes,
      else: class === classes
  end

  @doc false
  def maybe_include(attrs1, attrs2) do
    for { field, value } <- attrs2, value != nil, into: attrs1 do
      { field, value }
    end
  end

  defp to_attrs(nil), do: %{}
  defp to_attrs(collection) do
    for { field, value } <- collection, value != nil, into: %{} do
      { field, to_attr_value(value) }
    end
  end

  defp to_attr_value(nil),    do: nil
  defp to_attr_value([]),     do: nil
  defp to_attr_value([data]), do: to_attr_value(data)

  defp to_attr_value(list) when is_list(list) do
    res = for data <- list, data != nil do
      to_attr_value(data)
    end |> :lists.flatten()
    if res === [], do: nil, else: res
  end

  defp to_attr_value(%Eml.Parameter{} = param), do: param
  defp to_attr_value(param) when is_atom(param)
  and not param in [true, false], do: %Eml.Parameter{id: param, type: :attr}

  defp to_attr_value(data), do: to_string(data)

  @doc false
  def ensure_list(data) when is_list(data), do: data
  def ensure_list(""),                      do: []
  def ensure_list(data),                    do: [data]

end

# Enumerable protocol implementation

defimpl Enumerable, for: Eml.Markup do

  def count(_markup),           do: { :error, __MODULE__ }
  def member?(_markup, _),      do: { :error, __MODULE__ }

  def reduce(markup, acc, fun) do
    case reduce_content([markup], acc, fun) do
      { :cont, acc }    -> { :done, acc }
      { :suspend, acc } -> { :suspended, acc }
      { :halt, acc }    -> { :halted, acc }
    end
  end

  defp reduce_content(_, { :halt, acc }, _fun) do
    { :halt, acc }
  end
  defp reduce_content(content, { :suspend, acc }, fun) do
    { :suspend, acc, &reduce_content(content, &1, fun) }
  end
  defp reduce_content([%Eml.Markup{content: content} = markup | rest], { :cont, acc }, fun) do
    reduce_content(rest, reduce_content(content, fun.(markup, acc), fun), fun)
  end
  defp reduce_content([element | rest], { :cont, acc }, fun) do
    reduce_content(rest, fun.(element, acc), fun)
  end
  defp reduce_content([], acc, _fun) do
    acc
  end
end

# Inspect protocol implementation

defimpl Inspect, for: Eml.Markup do
  import Inspect.Algebra

  def inspect(%Eml.Markup{tag: tag, attrs: attrs, content: content}, opts) do
    opts = if is_list(opts), do: Keyword.put(opts, :hide_content_type, true), else: opts
    tag   = Atom.to_string(tag)
    attrs = if attrs == %{}, do: "", else: to_doc(attrs, opts)
    content  = if Eml.empty?(content), do: "", else: to_doc(content, opts)
    fields = case { attrs, content } do
               { "", "" } -> ""
               { "", _ }  -> content
               { _, "" }  -> attrs
               { _, _ }   -> glue(attrs, " ", content)
             end
    concat ["#", tag, "<", fields, ">"]
  end
end
