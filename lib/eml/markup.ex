defmodule Eml.Markup.Record do
  @moduledoc false

  defmacro __using__(_) do
    quote do
      defrecordp :m, Eml.Markup, tag: :div, id: nil, class: nil, attrs: [], content: []
    end
  end

  @doc false
  def to_list({ Eml.Markup, tag, id,  class,  attrs, content }) do
    [tag: tag, id: id, class: class, attrs: attrs, content: content]
  end

  @doc false
  def to_quote(tag, id, class, attrs, content) do
    quote do: { Eml.Markup, unquote(tag), unquote(id), unquote(class), unquote(attrs), unquote(content) }
  end
end

defmodule Eml.Markup do
  use Eml.Markup.Record

  @type data       :: Eml.data
  @type content    :: Eml.content

  @type attr_field :: atom
  @type attr_value :: binary | list(binary) | nil
  @type attrs      :: list({ attr_field, attr_value })

  @type t :: { Eml.Markup, atom, attr_value, attr_value, attrs, content }

  @type field :: { :tag, atom }
               | { :id, attr_value }
               | { :class, attr_value }
               | { :attrs, attrs }
               | { :content, data }

  @type fields :: list(field)

  @default_lang Eml.Language.Native

  @spec new() :: t
  def new do
    m()
  end

  @spec new(fields, Eml.lang) :: t
  def new(fields, lang // @default_lang) do
    tag     = fields[:tag] || :div
    id      = fields[:id]      |> to_attr_value()
    class   = fields[:class]   |> to_attr_value()
    attrs   = fields[:attrs]   |> to_attrs()
    content = fields[:content] |> Eml.read!(lang)
    m(tag: tag, id: id, class: class, attrs: attrs, content: content)
  end

  @spec tag(t) :: atom
  def tag(m(tag: tag)), do: tag

  @spec tag(t, atom) :: t
  def tag(markup, tag)
  when is_atom(tag), do: m(markup, tag: tag)

  @spec id(t) :: attr_value
  def id(m(id: id)), do: id

  @spec id(t, attr_value) :: t
  def id(markup, id),
  do: m(markup, id: to_attr_value(id))

  @spec class(t) :: attr_value
  def class(m(class: class)), do: class

  @spec class(t, attr_value) :: t
  def class(markup, class),
  do: m(markup, class: to_attr_value(class))

  @spec content(t) :: content
  def content(m(content: content)), do: content

  @spec content(t, data, Eml.lang) :: t
  def content(markup, data, lang // @default_lang) do
    m(markup, content: Eml.read!(data, lang))
  end

  @spec add(t, data, Keyword.t) :: t
  def add(m(content: current) = markup, data, opts // []) do
    at      = opts[:at] || :end
    lang  = opts[:lang] || @default_lang
    content = Eml.read!(data, current, at, lang)
    m(markup, content: content)
  end

  @spec update(t, (Eml.element -> data), Eml.lang) :: t
  def update(m(content: content) = markup, fun, lang // @default_lang) do
    content = lc element inlist content, data = fun.(element) do
      Eml.Readable.read(data, lang)
    end
    m(markup, content: content)
  end

  @spec remove(t, Eml.element | content) :: t
  def remove(m(content: content) = markup, to_remove) do
    to_remove = if is_list(to_remove), do: to_remove, else: [to_remove]
    content = lc element inlist content, not element in to_remove do
      element
    end
    m(markup, content: content)
  end

  @spec attrs(t) :: attrs
  def attrs(m(attrs: attrs)) do
    attrs
  end

  @spec attrs(t, attrs) :: t
  def attrs(m(attrs: current) = markup, attrs) do
    m(markup, attrs: Keyword.merge(current, to_attrs(attrs)))
  end

  @spec attr(t, atom) :: attr_value
  def attr(m(attrs: attrs), field) do
    Keyword.get(attrs, field)
  end

  @spec attr(t, atom, attr_value) :: t
  def attr(m(attrs: attrs) = markup, field, value) do
    m(markup, attrs: Keyword.put(attrs, field, to_attr_value(value)))
  end

  @spec insert_attr_value(t, atom, attr_value) :: t
  def insert_attr_value(m(attrs: attrs) = markup, field, value) do
    attrs = Keyword.update(attrs, field, to_attr_value(value), &insert_attr_value(&1, value))
    m(markup, attrs: attrs)
  end

  @spec remove_attr(t, atom) :: t
  def remove_attr(m(attrs: attrs) = markup, field) do
    m(markup, attrs: Keyword.delete(attrs, field))
  end

  @spec has?(t, Keyword.t) :: boolean
  def has?(m() = markup, opts) do
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
  def has?(_, _), do: false

  defp has_tag?(_, :any), do: true
  defp has_tag?(m(tag: etag), tag), do: tag === etag

  defp has_id?(_, :any), do: true
  defp has_id?(m(id: eid), id), do: id === eid

  defp has_class?(_, :any), do: true
  defp has_class?(m(class: eclass), classes) when is_list(classes) do
    Enum.all?(classes, &class?(&1, eclass))
  end
  defp has_class?(m(class: eclass), class), do: class?(class, eclass)

  defp has_content?(_, :any), do: true
  defp has_content?(m(content: econtent), content) do
    Enum.all?(content, &Kernel.in(&1, econtent))
  end

  defp has_attrs?(_, []), do: true
  defp has_attrs?(m(attrs: eattrs), attrs) do
    Enum.all?(attrs, fn attr ->
      attr?(attr, eattrs)
    end)
  end

  defp attr?({ field, value }, attrs) do
    Enum.any?(attrs, fn { f, v } ->
      field === f and (value === :any or value === v)
    end)
  end

  def match?(_, tag, id // :any, class // :any)

  def match?(_, :any, :any, :any),
  do: true

  def match?(m(tag: etag), tag, :any, :any),
  do: tag === etag

  def match?(m(id: eid), :any, id, :any),
  do: id === eid

  def match?(m(class: eclass), :any, :any, class),
  do: class?(class, eclass)

  def match?(m(tag: etag, id: eid), tag, id, :any),
  do: tag === etag and id === eid

  def match?(m(tag: etag, class: eclass), tag, :any, class),
  do: tag === etag and class?(class, eclass)

  def match?(m(id: eid, class: eclass), :any, id, class),
  do: id === eid and class?(class, eclass)

  def match?(m(tag: etag, id: eid, class: eclass), tag, id, class),
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
    maybe_include_acc(:lists.reverse(attrs2), attrs1)
  end

  defp maybe_include_acc([{ _field, nil } | attrs], acc), do: maybe_include_acc(attrs, acc)
  defp maybe_include_acc([attr | attrs], acc),            do: maybe_include_acc(attrs, [attr | acc])
  defp maybe_include_acc([], acc),                        do: acc

  defp to_attrs(data)
  when is_list(data) do
    lc { field, value } inlist data, not nil?(value) do
      { field, to_attr_value(value) }
    end
  end

  defp to_attrs(nil), do: []

  defp to_attr_value(nil),    do: nil
  defp to_attr_value([]),     do: nil
  defp to_attr_value([data]), do: to_attr_value(data)

  defp to_attr_value(list) when is_list(list) do
    res = lc data inlist list, not nil?(data) do
      to_attr_value(data)
    end |> :lists.flatten()
    if res === [], do: nil, else: res
  end

  defp to_attr_value(param)
  when is_record(param, Eml.Parameter), do: param
  defp to_attr_value(param)
  when is_atom(param)
  and not param in [true, false], do: Eml.Parameter.new(param, :attr)

  defp to_attr_value(data), do: to_string(data)

  defp insert_attr_value(old, new) do
    old = ensure_list(old)
    new = ensure_list(new)
    lc v inlist new do
      to_attr_value(v)
    end ++ old
  end

  defp ensure_list(data) when is_list(data), do: data
  defp ensure_list(""),                      do: []
  defp ensure_list(data),                    do: [data]

end

# Enumerable protocol implementation

defimpl Enumerable, for: Eml.Markup do
  use Eml.Markup.Record

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

  defp reduce_content([m(content: content) = markup | rest], { :cont, acc }, fun) do
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
  use Eml.Markup.Record
  import Inspect.Algebra

  def inspect(m(tag: tag, id: id, class: class, attrs: attrs, content: content), opts) do
    opts = if is_list(opts), do: Keyword.put(opts, :hide_content_type, true), else: opts
    tag   = atom_to_binary(tag)
    attrs = Eml.Markup.maybe_include(attrs, [id: id, class: class])
    attrs = if attrs == [], do: "", else: to_doc(attrs, opts)
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