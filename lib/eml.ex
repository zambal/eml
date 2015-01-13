defmodule Eml do
  alias Eml.Markup
  alias Eml.Template
  alias Eml.Readable

  @default_lang Eml.Language.Html

  @type element  :: binary | Eml.Markup.t | Eml.Parameter.t | Eml.Template.t
  @type content  :: [element]
  @type t        :: element | content
  @type data     :: Eml.Readable.t
  @type error    :: { :error, term }
  @type lang     :: atom
  @type path     :: binary

  @type unpackr_result  :: funpackr_result | [unpackr_result]
  @type funpackr_result :: binary | Eml.Parameter.t | Eml.Template.t | [binary | Eml.Parameter | Eml.Template.t]

  @moduledoc """
  TODO
  """

  @doc """
  Define eml content.

  Just like in other Elixir blocks, evaluates all expressions
  and returns the last. Code inside an eml block is just
  regular Elixir code. The purpose of the `eml/2` macro
  is to make it more convenient to write eml.

  It does this by doing two things:

  * Provide a lexical scope where all markup macro's are imported to
  * Read the last expression of the block in order to guarantee valid eml content

  To illustrate, the expressions below all produce the same output:

  * `eml do: div([], 42)`
  * `Eml.Markup.new(:div, %{}, 42) |> Eml.read!(Eml.Language.Native)`
  * `Eml.Markup.Html.div([], 42) |> Eml.read!(Eml.Language.Native)`

  Note that since the Elixir `Kernel` module by default imports the `div/2`
  function in to the global namespace, this function is inside an eml block
  only available as `Kernel.div/2`.

  Instead of defining a do block, you can also provide a path to a file
  with eml content. See `Eml.precompile_template/2` for an example with
  an external file.

  """
  defmacro eml(opts, block \\ []) do
    block = block[:do] || opts[:do]
    opts  = Keyword.put(opts, :type, :eml)
    do_eml(block, opts)
  end

  @doc false
  def do_eml(quoted \\ nil, opts) do
    type   = opts[:type] || :template
    lang   = opts[:use] || @default_lang
    file   = opts[:file]
    eval   = opts[:eval]
    env    = opts[:env] || __ENV__
    quoted = if file do
             file
             |> File.read!()
             |> Code.string_to_quoted!(file: file)
           else
             quoted || opts[:do]
           end
    ast  = case type do
            :template ->
              quote do
                use unquote(lang)
                Eml.compile unquote(quoted)
              end
            :html ->
              quote do
                use unquote(lang)
                Eml.write! unquote(quoted)
              end
            :eml ->
              quote do
                use unquote(lang)
                Eml.read! unquote(quoted), Eml.Language.Native
              end
          end
    if eval do
      { expr, _ } = Code.eval_quoted(ast, [] , env)
      Macro.escape(expr)
    else
      ast
    end
  end

  @doc """
  Define a function that produces eml.

  This macro is provided both for convenience and
  to be able to show intention of code.

  This:

  `defeml mydiv(content), do: div(%{}, content)`

  is effectively the same as:

  `def mydiv(content), do: eml do div(%{}, content) end`

  """
  defmacro defeml(call, do_block) do
    block = do_block[:do]
    ast   = do_eml(block, type: :eml)
    quote do
      def unquote(call) do
        unquote(ast)
      end
    end
  end

  @doc """
  Define a function that compiles eml to a template during compile time.

  The function that this macro defines accepts optionally a bindings
  object as argument for binding values to parameters. Note that because
  the code in the do block is evaluated at compile time, it's not possible
  to call other functions from the same module.

  Instead of defining a do block, you can also provide a path to a file with
  eml content.

  ### Example:

      iex> File.write! "test.eml.exs", "div [id: "name"], :name"
      iex> defmodule MyTemplates do
      ...>   use Eml
      ...>
      ...>   precompile_template test do
      ...>     prefix = "fruit"
      ...>     div do
      ...>       span [class: "prefix"], prefix
      ...>       span [class: "content"], :fruit
      ...>     end
      ...>   end
      ...>
      ...>   precompile_template from_file, file: "test.eml.exs"
      ...> end
      iex> MyTemplates.test
      #Template<[fruit: 1]>
      iex> MyTemplates.test fruit: "lemon"
      "<div><span class='prefix'>fruit</span><span class='content'>lemon</span></div>"
      iex> MyTemplates.from_file name: "Vincent"
      "<div id='name'>Vincent</div>"
      iex> File.rm! "test.eml.exs"
  """
  defmacro precompile_template(name, opts) do
    { name, _, nil } = name
    ast = opts
    |> Keyword.put(:type, :template)
    |> Keyword.put(:eval, true)
    |> do_eml()
    quote do
      def unquote(name)(bindings \\ []) do
        Eml.write!(unquote(ast), bindings: bindings)
      end
    end
  end

  @doc """
  Define a function that compiles eml to html during compile time.

  Note that because the code in the do block is evaluated at compile
  time, it's not possible to call other functions from the same module.

  Instead of defining a do block, you can also provide a path to a file
  with eml content. See `Eml.precompile_template/2` for an example with
  an external file.

  ### Example:

      iex> defmodule MyHtml do
      ...>   use Eml
      ...>
      ...>   precompile_html test do
      ...>     prefix  = "fruit"
      ...>     content = "lemon"
      ...>     div do
      ...>       span [class: "prefix"], prefix
      ...>       span [class: "content"], content
      ...>     end
      ...>   end
      ...> end
      iex> MyHtml.test
      "<div><span class='prefix'>fruit</span><span class='content'>lemon</span></div>"

  """
  defmacro precompile_html(name, opts) do
    ast = opts
    |> Keyword.put(:type, :html)
    |> Keyword.put(:eval, true)
    |> do_eml()
    quote do
      def unquote(name) do
        unquote(ast)
      end
    end
  end

  @doc """
  Selects content from arbritary eml.

  It will traverse the complete eml tree, so all elements are
  evaluated. There is however currently no way to select templates
  or parameters.

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


  ### Examples:

      iex> e = eml do
      ...>   div do
      ...>     span [id: "inner1", class: "inner"], "hello "
      ...>     span [id: "inner2", class: "inner"], "world"
      ...>   end
      ...> end
      [#div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
        #span<%{id: "inner2", class: "inner"} ["world"]>]>]
      iex> Eml.select(e, id: "inner1")
      [#span<%{id: "inner1", class: "inner"} ["hello "]>]
      iex> Eml.select(e, class: "inner")
      [#span<%{id: "inner1", class: "inner"} ["hello "]>,
       #span<%{id: "inner2", class: "inner"} ["world"]>]
      iex> Eml.select(e, class: "inner", id: "test")
      []
      iex> Eml.select(e, pat: ~r/h.*o/)
      ["hello "]
      iex> Eml.select(e, pat: ~r/H.*o/, parent: true)
      [#span<%{id: "inner1", class: "inner"} ["hello "]>]

  """
  @spec select(t) :: t
  def select(eml, opts \\ [])

  def select(content, opts) when is_list(content) do
    Enum.flat_map(content, &select(&1, opts))
  end

  def select(%Template{}, _opts), do: []

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
          Enum.any?(element.content, fn el -> is_binary(el) and Regex.match?(pat, el) end)
        end
        Enum.filter(element, pat_fun)
      else
        idclass_fun = fn element ->
          markup?(element) and
          Enum.any?(element.content, fn el -> Markup.match?(el, tag, id, class) end)
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
  Adds content to matched markup.

  It traverses and returns the complete eml tree.
  Markup is matched depending on the provided options.

  Those options can be:

  * `:tag` - match content by tag (`atom`)
  * `:id` - match content by id (`binary`)
  * `:class` - match content by class (`binary`)
  * `:at` -  add new content at begin or end of existing
    content, default is `:end` (`:begin | :end`)

  When `:tag`, `:id`, or `:class` are combined, only markup is
  selected that satisfies all conditions.


  ### Examples:

      iex> e = eml do
      ...>   div do
      ...>     span [id: "inner1", class: "inner"], "hello "
      ...>     span [id: "inner2", class: "inner"], "world"
      ...>   end
      ...> end
      [#div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
        #span<%{id: "inner2", class: "inner"} ["world"]>]>]
      iex> Eml.add(e, "dear ", id: "inner1")
      [#div<[#span<%{id: "inner1", class: "inner"} ["hello dear "]>,
        #span<%{id: "inner2", class: "inner"} ["world"]>]>]
      iex> Eml.add(e, "__", class: "inner", at: :begin)
      [#div<[#span<%{id: "inner1", class: "inner"} ["__hello "]>,
        #span<%{id: "inner2", class: "inner"} ["__world"]>]>]
      iex> Eml.add(e, (eml do: span "!"), tag: :div) |> Eml.write!(pretty: false)
      "<div><span id='inner1' class='inner'>hello </span><span id='inner2' class='inner'>world</span><span>!</span></div>"

  """
  @spec add(t, data, Keyword.t) :: t
  def add(eml, data, opts \\ []) do
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
  Updates matched content.

  When content is matched, the provided function will be evaluated
  with the matched content as argument.

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


  ### Examples:

      iex> e = eml do
      ...>   div do
      ...>     span [id: "inner1", class: "inner"], "hello "
      ...>     span [id: "inner2", class: "inner"], "world"
      ...>   end
      ...> end
      [#div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
        #span<%{id: "inner2", class: "inner"} ["world"]>]>]
      iex> Eml.update(e, fn m -> Markup.id(m, "outer") end, tag: :div)
      [#div<%{id: "outer"}
       [#span<%{id: "inner1", class: "inner"} ["hello "]>,
        #span<%{id: "inner2", class: "inner"} ["world"]>]>]
      iex> Eml.update(e, fn m -> Markup.id(m, "outer") end, id: "inner2", parent: true)
      [#div<%{id: "outer"}
       [#span<%{id: "inner1", class: "inner"} ["hello "]>,
        #span<%{id: "inner2", class: "inner"} ["world"]>]>]
      iex> Eml.update(e, fn s -> String.upcase(s) end, pat: ~r/.*/) |> Eml.write!(pretty: false)
      "<div><span id='inner1' class='inner'>HELLO </span><span id='inner2' class='inner'>WORLD</span></div>"

  """
  @spec update(t, (element -> data), Keyword.t) :: t
  def update(eml, fun, opts \\ []) do
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
            Enum.any?(element.content, fn el -> is_binary(el) and Regex.match?(pat, el) end),
              do: fun.(element),
            else: element
          end
        else
          fn element ->
            if markup?(element) and
            Enum.any?(element.content, fn el -> Markup.match?(el, tag, id, class) end),
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

  ### Examples:

      iex> e = eml do
      ...>   div do
      ...>     span [id: "inner1", class: "inner"], "hello "
      ...>     span [id: "inner2", class: "inner"], "world"
      ...>   end
      ...> end
      [#div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
        #span<%{id: "inner2", class: "inner"} ["world"]>]>]
      iex> Eml.remove(e, tag: :div)
      []
      iex> Eml.remove(e, id: "inner1")
      [#div<[#span<%{id: "inner2", class: "inner"} ["world"]>]>]
      iex> Eml.remove(e, pat: ~r/.*/)
      [#div<[#span<%{id: "inner1", class: "inner"}>,
        #span<%{id: "inner2", class: "inner"}>]>]

  """
  @spec remove(t, Keyword.t) :: t
  def remove(eml, opts \\ []) do
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
            Enum.any?(element.content, fn el -> is_binary(el) and Regex.match?(pat, el) end),
              do: nil,
            else: element
          end
        else
          fn element ->
            if markup?(element) and
            Enum.any?(element.content, fn el -> Markup.match?(el, tag, id, class) end),
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
  the provided options, returns false otherwise.

  In other words, returns true when the same select query
  would return a non-empty list.

  See `select/3` for a description of the provided options.

  ### Examples:

      iex> e = eml do
      ...>   div do
      ...>     span [id: "inner1", class: "inner"], "hello "
      ...>     span [id: "inner2", class: "inner"], "world"
      ...>   end
      ...> end
      [#div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
        #span<%{id: "inner2", class: "inner"} ["world"]>]>]
      iex> Eml.member?(e, id: "inner1")
      true
      iex> Eml.member?(e, class: "inner", id: "test")
      false
      iex> Eml.member?(e, pat: ~r/h.*o/)
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
  Recursively transforms content.

  This is the most low level operation provided by Eml for manipulating
  eml content. For example, `update/3` and `remove/2` are implemented by
  using this function.

  It accepts any eml and traverses all elements of the provided eml tree.
  The provided transform function will be evaluated for every element `transform/3`
  encounters. Parent elements will be transformed before their children. Child elements
  of a parent will be evaluated before moving to the next sibling.

  When the provided function returns `nil`, the the content will
  be removed from the eml tree. Any other returned value will be
  evaluated by `Eml.read!/2` in order to guarantee valid eml.

  Note that because parent elements are evaluated before their children,
  no children will be evaluated if the parent is removed.

  Accepts a lang as optional 3rd argument, in order to specify how transformed data
  should be interpreted, defaults to `Eml.Language.Native`

  ### Examples:

      iex> e = eml do
      ...>   div do
      ...>     span [id: "inner1", class: "inner"], "hello "
      ...>     span [id: "inner2", class: "inner"], "world"
      ...>   end
      ...> end
      [#div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
        #span<%{id: "inner2", class: "inner"} ["world"]>]>]
      iex> Eml.transform(e, fn x -> if Markup.has?(x, tag: :span), do: "matched", else: x end)
      [#div<["matched", "matched"]>]
      iex> Eml.transform(e, fn x ->
      ...> IO.puts(inspect x)
      ...> x end)
      #div<[#span<%{id: "inner1", class: "inner"} ["hello "]>, #span<%{id: "inner2", class: "inner"} ["world"]>]>
      #span<%{id: "inner1", class: "inner"} ["hello "]>
      "hello "
      #span<%{id: "inner2", class: "inner"} ["world"]>
      "world"
      [#div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
        #span<%{id: "inner2", class: "inner"} ["world"]>]>]

  """
  @spec transform(t, (element -> data), lang) :: t | nil
  def transform(eml, fun, lang \\ Eml.Language.Native)

  def transform(eml, fun, lang) when is_list(eml) do
    for element <- eml, t = transform(element, fun, lang), do: t
  end

  def transform(element, fun, lang) do
    case element |> fun.() |> Readable.read(lang) do
      { :error, _ } -> nil
      element ->
        if markup?(element),
          do: %Markup{element| content: transform(element.content, fun, lang)},
        else: element
    end
  end

  @doc """
  Reads data and converts it to eml

  How the data is interpreted depends on the `lang` argument.
  The default value is `Eml.Language.Html', which means that
  strings are parsed as html. The other language that is supported
  by default is `Eml.Language.Native`, which is for example used when
  setting content in an `Eml.Markup` element. Appart from the provided
  language, this function performs some conversions on its own. Mainly
  flattening of lists and concatenating binaries in a list.

  ### Examples:

      iex> Eml.read("<body><h1 id='main-title'>The title</h1></body>")
      [#body<[#h1<%{id: "main-title"} ["The title"]>]>]

      iex> Eml.read([1, 2, 3,[4, 5, "6"], " ", true, " ", [false]], Eml.Language.Native)
      ["123456 true false"]

  """
  @spec read(data, lang) :: t | error
  def read(data, lang \\ @default_lang) do
    read(data, [], :begin, lang)
  end

  @doc """
  Same as `Eml.read/2`, except that it raises an exception, instead of returning an
  error tuple in case of an error.
  """
  @spec read!(data, lang) :: t
  def read!(data, lang \\ @default_lang) do
    case read(data, lang) do
      { :error, e } ->
        raise ArgumentError, message: "Error #{inspect e}"
      eml -> eml
    end
  end

  @doc """
  Same as `Eml.read/2`, except that it reads data from a file
  """
  @spec read_file(path, lang) :: t | error
  def read_file(path, lang \\ @default_lang) do
    case File.read(path) do
      { :ok, data }  -> read(data, [], :begin, lang)
      { :error, e }  -> { :error, e }
    end
  end

  @doc """
  Same as `Eml.read_file/2`, except that it raises an exception, instead of
  returning an error tuple in case of an error.
  """
  @spec read_file!(path, lang) :: t | error
  def read_file!(path, lang \\ @default_lang) do
    File.read!(path) |> read!(lang)
  end

  @doc false
  @spec read(data | error, content, atom, lang) :: t | error
  def read(data, content, at, lang \\ Eml.Languages.Native)

  # Error pass through
  def read({ :error, e }, _, _, _), do: { :error, e }

  # No-ops
  def read(nondata, content, _, _)
  when nondata in [nil, "", []], do: content

  # Handle lists

  def read(data, content, :end, lang)
  when is_list(data), do: add_content(data, :lists.reverse(content), :end, lang) |> :lists.reverse()

  def read(data, content, :begin, lang)
  when is_list(data), do: add_content(:lists.reverse(data), content, :begin, lang)

  def read(data, content, mode, lang) do
    case Readable.read(data, lang) do
      { :error, e } -> { :error, e }
      element       -> add_element(element, content, mode)
    end
  end

  # Optimize for most comon cases

  defp add_element(element, [], _) when is_list(element),
  do: element

  defp add_element(element, [], _),
  do: [element]

  defp add_element(element, [current], :end) do
    if is_binary(element) and is_binary(current) do
      [current <> element]
    else
      [current, element]
    end
  end

  defp add_element(element, [current], :begin) do
    if is_binary(element) and is_binary(current) do
      [element <> current]
    else
      [element, current]
    end
  end

  defp add_element(element, [h | t], :end) do
    if is_binary(element) and is_binary(h) do
      [h <> element | t]
    else
      [element, h | t]
    end
  end

  defp add_element(element, [h | t], :begin) do
    if is_binary(element) and is_binary(h) do
      [element <> h | t]
    else
      [element, h | t]
    end
  end

  defp add_content([h | t], content, mode, lang) do
    content = if is_list(h) and mode === :end,
                do: add_content(h, content, mode, lang),
              else: read(h, content, mode, lang)
    add_content(t, content, mode, lang)
  end

  defp add_content([], content, _, _),
  do: content

  @doc false
  @spec read!(data | error, content, atom, lang) :: t
  def read!(data, content, at, lang \\ @default_lang) do
    case read(data, content, at, lang) do
      { :error, e } ->
        raise ArgumentError, message: "Error #{e}"
      content -> content
    end
  end

  @doc """
  Writes eml content to the specified language, which is
  html by default.

  The accepted options are:

  * `:lang` - The language to write to, by default `Eml.Language.Html`
  * `:quote` - The type of quotes used for attribute values. Accepted values are `:single` (default) and `:double`.
  * `:escape` - Escape `&`, `<` and `>` in attribute values and content to HTML entities.
     Accepted values are `true` (default) and `false`.
  * `:bindings` - When the provided eml contains a template, you can bind its parameters by providing a
     Keyword list where the keys are the parameter id's. See `Eml.compile/2` for an example.

  ### Examples:

      iex> Eml.write (eml do: body([], h1([id: "main-title"], "A title")))
      {:ok, "<body><h1 id='main-title'>A title</h1></body>"}

      iex> Eml.write (eml do: body([], h1([id: "main-title"], "A title"))), quote: :double
      {:ok, "<body><h1 id=\"main-title\">A title</h1></body>"}

      iex> Eml.write (eml do: p([], "Tom & Jerry"))
      {:ok, "<p>Tom &amp; Jerry</p>"}

  """
  @spec write(t, Keyword.t) :: { :ok, binary } | error
  def write(eml, opts \\ [])

  def write(%Template{} = t, opts) do
    { lang, opts } = Keyword.pop(opts, :lang, @default_lang)
    lang.write(t, Keyword.put(opts, :mode, :compile))
  end

  def write(eml, opts) do
    { lang, opts } = Keyword.pop(opts, :lang, @default_lang)
    lang.write(eml, Keyword.put(opts, :mode, :render))
  end

  @doc """
  Same as `Eml.write/2`, except that it raises an exception, instead of returning an
  error tuple in case of an error.
  """
  @spec write!(t, Keyword.t) :: binary
  def write!(eml, opts \\ []) do
    case write(eml, opts) do
      { :ok, str }  -> str
      { :error, e } -> raise ArgumentError, message: inspect(e, pretty: true)
    end
  end

  @doc """
  Same as `Eml.write/2`, except that it writes the results to a file
  """
  @spec write_file(path, t, Keyword.t) :: :ok | error
  def write_file(path, eml, opts \\ []) do
    case write(eml, opts) do
      { :ok, str } -> File.write(path, str)
      error        -> error
    end
  end

  @doc """
  Same as `Eml.write_file/2`, except that it raises an exception, instead of returning an
  error tuple in case of an error.
  """
  @spec write_file!(path, t, Keyword.t) :: :ok
  def write_file!(path, eml, opts \\ []) do
    File.write!(path, write!(eml, opts))
  end


  @doc """
  Same as `Eml.write/2` except that it always returns a template.

  ### Examples:

      iex> t = Eml.compile (eml do: body([], h1([id: "main-title"], :the_title)))
      #Template<[the_title: 1]>
      iex> Eml.write(t, bindings: [the_title: "The Title"])
      {:ok, "<body><h1 id='main-title'>The Title</h1></body>"}

  """
  @spec compile(t, lang) :: Eml.Template.t | error
  def compile(eml, lang \\ @default_lang)

  def compile(%Template{} = t, _), do: t
  def compile(eml, lang) do
    # for consistence, when compiling eml we always want to return a template, even if
    # there are no parameters at all, or all of them are bound.
    case lang.write(eml, [mode: :compile, force_templ: true]) do
      { :ok, t } -> t
      error      -> error
    end
  end

  @doc """
  Extracts a value from content (which is always a list) or markup

  ### Examples

      iex> unpack ["42"]
      "42"

      iex> unpack 42
      42

      iex> unpack (eml do: div([], "hallo"))
      #div<["hallo"]>

      iex> unpack unpack (eml do: div([], "hallo"))
      "hallo"

  """
  @spec unpack(t) :: t
  def unpack(%Markup{content: [element]}), do: element
  def unpack(%Markup{content: content}),   do: content
  def unpack([element]),                   do: element
  def unpack(eml),                         do: eml

  @doc """
  Extracts a value recursively from content or markup

  ### Examples

      iex> Eml.unpackr eml do: div([], 42)
      "42"

      iex> Eml.unpackr eml do: div([], [span([], "Hallo"), span([], " world")])
      ["Hallo", " world"]

  """
  @spec unpackr(t) :: unpackr_result
  def unpackr(%Markup{content: [element]}),   do: unpackr(element)
  def unpackr(%Markup{content: content}),     do: unpack_content(content)
  def unpackr([element]),                     do: unpackr(element)
  def unpackr(content) when is_list(content), do: unpack_content(content)
  def unpackr(element),                       do: element

  defp unpack_content(content) do
    for element <- content, do: unpackr(element)
  end

  @doc """
  Extracts a value recursively from content or markup and flatten the results.
  """
  @spec funpackr(t) :: funpackr_result
  def funpackr(eml), do: unpackr(eml) |> :lists.flatten

  @doc "Checks if a term is a `Eml.Markup` struct."
  @spec markup?(term) :: boolean
  def markup?(%Markup{}), do: true
  def markup?(_),   do: false

  @doc "Checks if a value is regarded as empty by Eml."
  @spec empty?(term) :: boolean
  def empty?(nil), do: true
  def empty?([]), do: true
  def empty?(%Markup{content: []}), do: true
  def empty?(_), do: false

  @doc """
  Returns the type of content.

  The types are `:content`, `:binary`, `:markup`, `:template`, `:parameter`, or `:undefined`.
  """
  @spec type(content) :: :content | :binary | :markup | :template | :parameter | :undefined
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

  def type(%Markup{}), do: :markup

  def type(%Template{}), do: :template

  def type(%Eml.Parameter{}), do: :parameter

  def type(_), do: :undefined

  # use Eml

  defmacro __using__(opts) do
    imports =
      if opts[:imports] != false do
        quote do
          import Eml, only: [eml: 1, defeml: 2, precompile_template: 2, precompile_html: 2, unpack: 1]
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
