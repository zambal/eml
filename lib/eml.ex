defmodule Eml do
  alias Eml.Markup
  alias Eml.Template
  alias Eml.Readable
  use Eml.Markup.Record
  alias Eml.Markup.Record, as: R
  use Eml.Template.Record


  @default_markup Eml.Markup.Html
  @default_reader Eml.Readers.Html
  @default_writer Eml.Writers.Html

  @type element  :: binary | Eml.Markup.t | Eml.Parameter.t | Eml.Template.t
  @type content  :: [element]
  @type t        :: element | content
  @type data     :: Eml.Readable.t
  @type error    :: { :error, term }
  @type reader   :: atom
  @type writer   :: atom
  @type path     :: binary

  @type unpackr_result  :: funpackr_result | [unpackr_result]
  @type funpackr_result :: binary | Eml.Parameter.t | Eml.Template.t | [binary | Eml.Parameter | Eml.Template.t]

  @doc """
  Define eml content.

  Just like in other Elixir blocks, evaluates all expressions
  and returns the last. Code inside an eml block is just 
  regular Elixir code. The purpose of the `eml/2` macro
  is to make it more convenient to write eml.  

  It does this by doing two things:

  * Provide a lexical scope where al markup macro's are imported to
  * Read the last expression of the block in order to guarantee valid eml content

  To illustrate, the expressions below all produce the same output:

  * `eml do: div 42`
  * `Eml.Markup.new(tag: :div, content: 42) |> Eml.read!(Eml.Readers.Native)`
  * `Eml.Markup.Html.div(42) |> Eml.read!(Eml.Readers.Native)`

  Note that since the Elixir `Kernel` module by default imports the `div/2`
  macro in to the global namespace, this macro is inside an eml block only
  available as `Kernel.div/2`

  """
  defmacro eml(opts // [], do_block) do
    opts    = Keyword.merge(opts, do_block)
    markup  = opts[:use] || @default_markup
    expr    = opts[:do]
    quote do
      (fn ->
         use unquote(markup)
         Eml.read! unquote(expr), Eml.Readers.Native
       end).()
    end
  end

  @doc """
  Define a function that produces eml. This macro is
  provided both for convenience and to be able to show
  intention of code.

  This:

  `defmarkup mydiv(content), do: div content`

  is effectively the same as:

  `def mydiv(content), do: eml do div content end`

  """
  defmacro defmarkup(call, do_block) do
    markup   = do_block[:use] || @default_markup
    expr     = do_block[:do]
    quote do
      def unquote(call) do
        use unquote(markup)
        Eml.read! unquote(expr), Eml.Readers.Native
      end
    end
  end

  @doc """
  Selects content from arbritary eml. It will traverse the
  complete eml tree, so all elements are evaluated. There
  is however currently no way to select templates or parameters.

  Content is matched depending on the provided options.

  Those options can be:

  * `:tag` - match markup content by tag (`atom`)
  * `:id` - match markup content by id (`binary`)
  * `:class` - match markup content by class (`binary`)
  * `:pat` - match binary content by regular expression (`RegEx.t`)
  * `:parent` - when set to true, selects the parent element
    of the matched content (`boolean`)

  When `:tag`, `:id`, or `:class` are combined, only markup is
  selected that satisfies all conditions.

  When the `:pat` options is used, `:tag`, `:id` and `:class` will
  be ignored.


  ## Examples:

      iex> e = eml do
      ...>   div do
      ...>     span [id: "inner1", class: "inner"], "hello "
      ...>     span [id: "inner2", class: "inner"], "world"
      ...>   end
      ...> end
      [#div<[#span<[id: "inner1", class: "inner"] ["hello "]>,
        #span<[id: "inner2", class: "inner"] ["world"]>]>]

      iex> Eml.select(e, id: "inner1")
      [#span<[id: "inner1", class: "inner"] ["hello "]>]

      iex> Eml.select(e, class: "inner")
      [#span<[id: "inner1", class: "inner"] ["hello "]>,
       #span<[id: "inner2", class: "inner"] ["world"]>]

      iex> Eml.select(e, class: "inner", id: "test")
      []

      iex> Eml.select(e, pat: %r/h.*o/)
      ["hello "]

      iex> Eml.select(e, pat: %r/H.*o/, parent: true)
      [#span<[id: "inner1", class: "inner"] ["hello "]>]

  """
  @spec select(t) :: t
  def select(eml, opts // [])

  def select(content, opts) when is_list(content) do
    Enum.flat_map(content, &select(&1, opts))
  end

  def select(template, _opts)
  when is_record(template, Template), do: []

  def select(element, opts) do
    tag            = opts[:tag] || :any
    id             = opts[:id] || :any
    class          = opts[:class] || :any
    pat            = opts[:pat]
    select_parent? = opts[:parent] || false
    if select_parent? do
      if pat do
        pat_fun = fn element ->
          markup?(element) and
          Enum.any?(content(element), fn el -> is_binary(el) and Regex.match?(pat, el) end)
        end
        Enum.filter(element, pat_fun)
      else
        idclass_fun = fn element ->
          markup?(element) and
          Enum.any?(content(element), fn el -> Markup.match?(el, tag, id, class) end)
        end
        Enum.filter(element, idclass_fun)
      end
    else
      if pat do
        pat_fun = fn
          element when is_binary(element) -> Regex.match?(pat, element)
          _                         -> false
        end
        Enum.filter(element, pat_fun)
      else
        Enum.filter(element, &Markup.match?(&1, tag, id, class))
      end
    end
  end

  @doc """
  Adds content to matched markup. It traverses and returns the
  complete eml tree.

  Markup is matched depending on the provided options.

  Those options can be:

  * `:tag` - match content by tag (`atom`)
  * `:id` - match content by id (`binary`)
  * `:class` - match content by class (`binary`)
  * `:at` -  add new content at begin or end of existing
    content, default is `:end` (`:begin | :end`)

  When `:tag`, `:id`, or `:class` are combined, only markup is
  selected that satisfies all conditions.


  ## Examples:

      iex> e = eml do
      ...>   div do
      ...>     span [id: "inner1", class: "inner"], "hello "
      ...>     span [id: "inner2", class: "inner"], "world"
      ...>   end
      ...> end
      [#div<[#span<[id: "inner1", class: "inner"] ["hello "]>,
        #span<[id: "inner2", class: "inner"] ["world"]>]>]

      iex> Eml.add(e, "dear ", id: "inner1")
      [#div<[#span<[id: "inner1", class: "inner"] ["hello dear "]>,
        #span<[id: "inner2", class: "inner"] ["world"]>]>]

      iex> Eml.add(e, "__", class: "inner", at: :begin)
      [#div<[#span<[id: "inner1", class: "inner"] ["__hello "]>,
        #span<[id: "inner2", class: "inner"] ["__world"]>]>]

      iex> Eml.add(e, (eml do: span "!"), tag: :div) |> Eml.write!(pretty: false)
      "<div><span id='inner1' class='inner'>hello </span><span id='inner2' class='inner'>world</span><span>!</span></div>"

  """
  @spec add(t, data, Keyword.t) :: t
  def add(eml, data, opts // []) do
    tag     = opts[:tag] || :any
    id      = opts[:id] || :any
    class   = opts[:class] || :any
    add_fun = fn element ->
      if markup?(element) and Markup.match?(element, tag, id, class),
        do:   Markup.add(element, data, opts),
        else: element
    end
    transform(eml, add_fun)
  end

  @doc """
  Updates matched content. When content is matched,
  the provided function will be evaluated with the
  matched content as argument.

  When the provided function returns `nil`, the the content will
  be removed from the eml tree. Any other returned value will be
  evaluated by `Eml.read!/2` in order to guarantee valid eml.

  Content is matched depending on the provided options.

  Those options can be:

  * `:tag` - match markup content by tag (`atom`)
  * `:id` - match markup content by id (`binary`)
  * `:class` - match markup content by class (`binary`)
  * `:pat` - match binary content by regular expression (`RegEx.t`)
  * `:parent` - when set to true, selects the parent element
    of the matched content (`boolean`)

  When `:tag`, `:id`, or `:class` are combined, only markup is
  selected that satisfies all conditions.

  When the `:pat` options is used, `:tag`, `:id` and `:class` will
  be ignored.


  ## Examples:

      iex> e = eml do
      ...>   div do
      ...>     span [id: "inner1", class: "inner"], "hello "
      ...>     span [id: "inner2", class: "inner"], "world"
      ...>   end
      ...> end
      [#div<[#span<[id: "inner1", class: "inner"] ["hello "]>,
        #span<[id: "inner2", class: "inner"] ["world"]>]>]

      iex> Eml.update(e, fn m -> Markup.id(m, "outer") end, tag: :div)
      [#div<[id: "outer"]
       [#span<[id: "inner1", class: "inner"] ["hello "]>,
        #span<[id: "inner2", class: "inner"] ["world"]>]>]

      iex> Eml.update(e, fn m -> Markup.id(m, "outer") end, id: "inner2", parent: true)
      [#div<[id: "outer"]
       [#span<[id: "inner1", class: "inner"] ["hello "]>,
        #span<[id: "inner2", class: "inner"] ["world"]>]>]

      iex> Eml.update(e, fn s -> String.upcase(s) end, pat: %r/.*/) |> Eml.write!(pretty: false)
      "<div><span id='inner1' class='inner'>HELLO </span><span id='inner2' class='inner'>WORLD</span></div>"

  """
  @spec update(t, (element -> data), Keyword.t) :: t
  def update(eml, fun, opts // []) do
    tag            = opts[:tag] || :any
    id             = opts[:id] || :any
    class          = opts[:class] || :any
    pat            = opts[:pat]
    update_parent? = opts[:parent] || false
    update_fun     =
     if update_parent? do
       if pat do
          fn element ->
            if markup?(element) and
            Enum.any?(content(element), fn el -> is_binary(el) and Regex.match?(pat, el) end),
              do: fun.(element),
            else: element
          end
        else
          fn element ->
            if markup?(element) and
            Enum.any?(content(element), fn el -> Markup.match?(el, tag, id, class) end),
              do: fun.(element),
            else: element
          end
        end
      else
        if pat do
          fn element ->
            if is_binary(element) and Regex.match?(pat, element),
             do: fun.(element),
           else: element
          end
        else
          fn element ->
            if Markup.match?(element, tag, id, class),
              do: fun.(element),
            else: element
          end
        end
     end
    transform(eml, update_fun)
  end

  @doc """
  Removes matched content from the eml tree.

  See `update/3` for a description of the provided options.

  ## Examples:

      iex> e = eml do
      ...>   div do
      ...>     span [id: "inner1", class: "inner"], "hello "
      ...>     span [id: "inner2", class: "inner"], "world"
      ...>   end
      ...> end
      [#div<[#span<[id: "inner1", class: "inner"] ["hello "]>,
        #span<[id: "inner2", class: "inner"] ["world"]>]>]

      iex> Eml.remove(e, tag: :div)
      []

      iex> Eml.remove(e, id: "inner1")
      [#div<[#span<[id: "inner2", class: "inner"] ["world"]>]>]

      iex> Eml.remove(e, pat: %r/.*/)   
      [#div<[#span<[id: "inner1", class: "inner"]>,
        #span<[id: "inner2", class: "inner"]>]>]

  """
  @spec remove(t, Keyword.t) :: t
  def remove(eml, opts // []) do
    tag            = opts[:tag] || :any
    id             = opts[:id] || :any
    class          = opts[:class] || :any
    pat            = opts[:pat]
    remove_parent? = opts[:parent] || false
    remove_fun     =
      if remove_parent? do
        if pat do
          fn element ->
            if markup?(element) and
            Enum.any?(content(element), fn el -> is_binary(el) and Regex.match?(pat, el) end),
              do: nil,
            else: element
          end
        else
          fn element ->
            if markup?(element) and
            Enum.any?(content(element), fn el -> Markup.match?(el, tag, id, class) end),
              do: nil,
            else: element
          end
        end
      else
        if pat do
          fn element ->
            if is_binary(element) and Regex.match?(pat, element),
             do: nil,
           else: element
          end
        else
          fn element ->
            if Markup.match?(element, tag, id, class),
              do: nil,
            else: element
          end
        end
    end
    transform(eml, remove_fun)
  end

  @doc """
  Returns true if there's at least one match with
  the provided options, returns false otherwise. In other words,
  returns true when the same select query would return a non-empty list.

  See `select/3` for a description of the provided options.

  ## Examples:

      iex> e = eml do
      ...>   div do
      ...>     span [id: "inner1", class: "inner"], "hello "
      ...>     span [id: "inner2", class: "inner"], "world"
      ...>   end
      ...> end
      [#div<[#span<[id: "inner1", class: "inner"] ["hello "]>,
        #span<[id: "inner2", class: "inner"] ["world"]>]>]

      iex> Eml.member?(e, id: "inner1")
      true

      iex> Eml.member?(e, class: "inner", id: "test")
      false

      iex> Eml.member?(e, pat: %r/h.*o/)
      true

  """
  @spec member?(t, Keyword.t) :: boolean
  def member?(eml, opts) do
    case select(eml, opts) do
      [] -> false
      _  -> true
    end
  end

  @doc """
  Recursively transforms content. This is the most low level operation
  provided by Eml for manipulating eml content. For example, `update/3`
  and `remove/2` are implemented by using this function. 

  It accepts any eml and traverses all elements of the provided eml tree.
  The provided transform function will be evaluated for every element `transform/3`
  encounters. Parent elements will be transformed before their children. Child elements
  of a parent will be evaluated before moving to the next sibling.

  When the provided function returns `nil`, the the content will
  be removed from the eml tree. Any other returned value will be
  evaluated by `Eml.read!/2` in order to guarantee valid eml.

  Note that because parent elements are evaluated before their children,
  no children will be evaluated if the parent is removed.

  Accepts a reader as optional 3rd argument, in order to specify how transformed data
  should be interpreted, defaults to `Eml.Readers.Native`

  ## Examples:

      iex> e = eml do
      ...>   div do
      ...>     span [id: "inner1", class: "inner"], "hello "
      ...>     span [id: "inner2", class: "inner"], "world"
      ...>   end
      ...> end
      [#div<[#span<[id: "inner1", class: "inner"] ["hello "]>,
        #span<[id: "inner2", class: "inner"] ["world"]>]>]
      
      iex> Eml.transform(e, fn x -> if Markup.has?(x, tag: :span), do: "matched", else: x end)
      [#div<["matched", "matched"]>]

      iex> Eml.transform(e, fn x ->
      ...> IO.puts(inspect x)
      ...> x end)
      #div<[#span<[id: "inner1", class: "inner"] ["hello "]>, #span<[id: "inner2", class: "inner"] ["world"]>]>
      #span<[id: "inner1", class: "inner"] ["hello "]>
      "hello "
      #span<[id: "inner2", class: "inner"] ["world"]>
      "world"

      [#div<[#span<[id: "inner1", class: "inner"] ["hello "]>,
        #span<[id: "inner2", class: "inner"] ["world"]>]>]
  """
  @spec transform(t, (element -> data), reader) :: t | nil
  def transform(eml, fun, reader // Eml.Readers.Native)

  def transform(eml, fun, reader) when is_list(eml) do
    lc element inlist eml, t = transform(element, fun, reader), do: t
  end

  def transform(element, fun, reader) do
    case element |> fun.() |> Readable.read(reader) do
      { :error, _ } -> nil
      element ->
        if markup?(element),
          do: m(element, content: transform(content(element), fun, reader)),
        else: element
    end
  end

  @spec read(data, reader) :: t | error
  def read(data, reader // @default_reader) do
    read(data, [], :begin, reader)
  end

  @spec read!(data, reader) :: t
  def read!(data, reader // @default_reader) do
    case read(data, reader) do
      { :error, e } ->
        raise ArgumentError, message: "Error #{inspect e}"
      eml -> eml
    end
  end

  @spec read_file(path, reader) :: t | error
  def read_file(path, reader // @default_reader) do
    case File.read(path) do
      { :ok, data }  -> read(data, [], :begin, reader)
      { :error, e }  -> { :error, e }
    end
  end

  @spec read_file!(path, reader) :: t | error
  def read_file!(path, reader // @default_reader) do
    File.read!(path) |> read!(reader)
  end

  @spec read(data | error, content, atom, reader) :: t | error
  def read(data, content, at, reader // Eml.Readers.Native)

  # Error pass through
  def read({ :error, e }, _, _, _), do: { :error, e }

  # No-ops
  def read(nondata, content, _, _)
  when nondata in [nil, "", []], do: content

  # Handle lists

  def read(data, content, :end, reader)
  when is_list(data), do: add_content(data, :lists.reverse(content), :end, reader) |> :lists.reverse()

  def read(data, content, :begin, reader)
  when is_list(data), do: add_content(:lists.reverse(data), content, :begin, reader)

  def read(data, content, mode, reader) do
    case Readable.read(data, reader) do
      { :error, e } -> { :error, e }
      element       -> add_element(element, content, mode)
    end
  end

  # Optimize for most comon cases

  def add_element(element, [], _),
  do: [element]

  def add_element(element, [current], :end) do
    if is_binary(element) and is_binary(current) do
      [current <> element]
    else
      [current, element]
    end
  end

  def add_element(element, [current], :begin) do
    if is_binary(element) and is_binary(current) do
      [element <> current]
    else
      [element, current]
    end
  end

  def add_element(element, [h | t], :end) do
    if is_binary(element) and is_binary(h) do
      [h <> element | t]
    else
      [element, h | t]
    end
  end

  def add_element(element, [h | t], :begin) do
    if is_binary(element) and is_binary(h) do
      [element <> h | t]
    else
      [element, h | t]
    end
  end

  defp add_content([h | t], content, mode, reader) do
    content = if is_list(h) and mode === :end,
                do: add_content(h, content, mode, reader),
              else: read(h, content, mode, reader)
    add_content(t, content, mode, reader)
  end

  defp add_content([], content, _, _),
  do: content

  @spec read!(data | error, content, atom, reader) :: t
  def read!(data, content, at, reader // @default_reader) do
    case read(data, content, at, reader) do
      { :error, e } ->
        raise ArgumentError, message: "Error #{e}"
      content -> content
    end
  end

  @spec write(t, Keyword.t) :: { :ok, binary } | error
  def write(eml, opts // [])

  def write(eml, opts) do
    { writer, opts } = Keyword.pop(opts, :writer, @default_writer)
    writer.write(eml, opts)
  end

  @spec write!(t, Keyword.t) :: binary
  def write!(eml, opts // []) do
    case write(eml, opts) do
      { :ok, str }  -> str
      { :error, e } -> raise ArgumentError, message: inspect(e, pretty: true)
    end
  end

  @spec write_file(path, t, Keyword.t) :: :ok | error
  def write_file(path, eml, opts // []) do
    case write(eml, opts) do
      { :ok, str } -> File.write(path, str)
      error        -> error
    end
  end

  @spec write_file!(path, t, Keyword.t) :: :ok
  def write_file!(path, eml, opts // []) do
    File.write!(path, write!(eml, opts))
  end

  @spec unpack(t) :: t
  def unpack(m(content: [element])), do: element
  def unpack(m(content: content)),   do: content
  def unpack([element]),             do: element
  def unpack(eml),                   do: eml

  @spec unpackr(t) :: unpackr_result
  def unpackr(m(content: [element])),         do: unpackr(element)
  def unpackr(m(content: content)),           do: unpack_content(content)
  def unpackr([element]),                     do: unpackr(element)
  def unpackr(content) when is_list(content), do: unpack_content(content)
  def unpackr(element),                       do: element

  defp unpack_content(content) do
    lc element inlist content, do: unpackr(element)
  end

  @spec funpackr(t) :: funpackr_result
  def funpackr(eml), do: unpackr(eml) |> :lists.flatten

  @spec content(Eml.Markup.t) :: t
  def content(m(content: content)), do: content

  @spec markup?(term) :: boolean
  def markup?(m()), do: true
  def markup?(_),   do: false

  @spec empty?(term) :: boolean
  def empty?(nil), do: true
  def empty?([]), do: true
  def empty?(m(content: [])), do: true
  def empty?(_), do: false

  defmacro match!(opts // []) do
    any      = quote do: _
    tag      = Keyword.get(opts, :tag, any)
    id       = Keyword.get(opts, :id, any)
    class    = Keyword.get(opts, :class, any)
    attrs    = Keyword.get(opts, :attrs, any)
    content  = Keyword.get(opts, :content, any)
    to_match = R.to_quote(tag, id, class, attrs, content)
    quote do
      unquote(to_match)
    end
  end

  defmacro match?(markup, opts // []) do
    quote do
      case unquote(markup) do
        Eml.match!(unquote(opts)) -> true
        _no_match                 -> false
      end
    end
  end

  def type(content)
  when is_list(content) do
    if Enum.any?(content, fn el -> type(el) === :undefined end) do
      :undefined
    else
      :content
    end
  end

  def type(bin)
  when is_binary(bin), do: :binary

  def type(m()), do: :markup

  def type(templ()), do: :template

  def type(other) do
    if Eml.Parameter.param?(other),
      do: :param,
    else: :undefined
  end
  # use Eml

  defmacro __using__(opts) do
    imports =
      if opts[:imports] != false do
        quote do
          import Eml, only: [eml: 1, defmarkup: 2, unpack: 1, content: 1, match!: 0, match!: 1]
        end
      else
        quote do: require Eml
      end
    aliases =
      if opts[:aliases] != false do
        quote do
          alias Eml.Markup
          alias Eml.Template
        end
      end
    quote do
      require Eml.Markup
      unquote(imports)
      unquote(aliases)
    end
  end
end
