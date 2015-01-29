defmodule Eml do
  @moduledoc """
  Eml stands for Elixir Markup Language. It provides a flexible and
  modular toolkit for generating, parsing and manipulating markup,
  written in the Elixir programming language. It's main focus is
  html, but other markup languages could be implemented as well.

  To start off:

  This piece of code
  ```elixir
  use Eml.Language.HTML

  name = "Vincent"
  age  = 36

  div class: "person" do
    div do
      span "name: "
      span name
    end
    div do
      span "age: "
      span age
    end
  end |> Eml.render!
  ```

  produces
  ```html
  <div class='person'>
    <div>
      <span>name: </span>
      <span>Vincent</span>
    </div>
    <div>
      <span>age: </span>
      <span>36</span>
    </div>
  </div>
  ```

  The functions and macro's in the `Eml` module are the bread and butter
  of the Eml library.
  """

  alias Eml.Element
  alias Eml.Template
  alias Eml.Data

  @default_lang Eml.Language.HTML

  @type t             :: String.t | Eml.Element.t | Eml.Parameter.t | Eml.Template.t
  @type enumerable    :: Eml.Element.t | [Eml.Element.t]
  @type transformable :: t | [t]
  @type error         :: { :error, term }
  @type lang          :: module

  @type unpackr_result  :: funpackr_result | [unpackr_result]
  @type funpackr_result :: String.t | Eml.Parameter.t | Eml.Template.t | [String.t | Eml.Parameter | Eml.Template.t]

  @doc false
  def do_eml(quoted \\ nil, opts) do
    type   = opts[:type] || :template
    lang   = opts[:use] || @default_lang
    file   = opts[:file]
    env    = opts[:env] || __ENV__
    quoted = if file do
             file
             |> File.read!()
             |> Code.string_to_quoted!(file: file, line: 1)
           else
             quoted || opts[:do]
           end
    ast  = case type do
            :template ->
              quote do
                use unquote(lang)
                Eml.compile! unquote(quoted)
              end
            :markup ->
              quote do
                use unquote(lang)
                Eml.render! unquote(quoted)
              end
            :eml ->
              quote do
                use unquote(lang)
                unquote(quoted)
              end
          end
    if opts[:precompile] do
      { expr, _ } = Code.eval_quoted(ast, [] , env)
      expr
    else
      ast
    end
  end

  @doc """
  Define a function that produces eml.

  This macro is provided both for convenience and
  to be able to show intention of code.

  This:

  ```elixir
  defeml mydiv(content), do: div(content)
  ```

  is effectively the same as:

  ```elixir
  def mydiv(content) do 
    use Eml.Language.HTML
    div(content)
  end
  ```

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
  Define a function that produces html.

  This macro is provided both for convenience and
  to be able to show intention of code.

  This:

  ```elixir
  defhtml mydiv(content), do: div(content)
  ```

  is effectively the same as:

  ```elixir
  def mydiv(content) do
    use Eml.Language.HTML
    div(content) |> Eml.render!()
  end
  ```

  """
  defmacro defhtml(call, do_block) do
    block = do_block[:do]
    ast   = do_eml(block, type: :markup, use: Eml.Language.HTML)
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

  When you ommit the name, this macro can also be used to precompile a
  block or file inside any function.

  ### Example:

      iex> File.write! "test.eml.exs", "div [id: "name"], :name"
      iex> defmodule MyTemplates do
      ...>   use Eml
      ...>
      ...>   precompile test1 do
      ...>     prefix = "fruit"
      ...>     div do
      ...>       span [class: "prefix"], prefix
      ...>       span [class: "content"], :fruit
      ...>     end
      ...>   end
      ...>
      ...>   precompile from_file, file: "test.eml.exs"
      ...>
      ...>   defhtml test2 do
      ...>     precompiled = precompile do
      ...>       # Everything inside this block is evaluated at compile time
      ...>       p [], :fruit
      ...>     end
      ...>
      ...>     # the rest of the function is evaluated at runtime
      ...>     body do
      ...>       bind precompiled, fruit: "Strawberry"
      ...>     end
      ...>   end
      ...> end
      iex> File.rm! "test.eml.exs"
      iex> MyTemplates.test1
      #Template<[:fruit]>
      iex> MyTemplates.test fruit: "lemon"
      "<div><span class='prefix'>fruit</span><span class='content'>lemon</span></div>"
      iex> MyTemplates.from_file name: "Vincent"
      "<div id='name'>Vincent</div>"
      iex> MyTemplated.test2
      "<body><p>Strawberry</p></body>"

  """

  defmacro precompile(name \\ nil, opts) do
    ast = opts
    |> Keyword.put(:type, :template)
    |> Keyword.put(:precompile, true)
    |> do_eml()
    |> Macro.escape()
    if is_nil(name) do
      quote do
        unquote(ast)
      end
    else
      { name, _, nil } = name
      quote do
        def unquote(name)(bindings \\ []) do
          Eml.compile!(unquote(ast), bindings)
        end
      end
    end
  end

  @doc """
  Selects content from arbritary eml.

  It will traverse the complete eml tree, so all nodes are
  evaluated. There is however currently no way to select templates
  or parameters.

  Nodes are matched depending on the provided options.

  Those options can be:

  * `:tag` - match element by tag (`atom`)
  * `:id` - match element by id (`binary`)
  * `:class` - match element by class (`binary`)
  * `:pat` - match binary content by regular expression (`RegEx.t`)
  * `:parent` - when set to true, selects the parent node
    of the matched node (`boolean`)

  When `:tag`, `:id`, or `:class` are combined, only elements are
  selected that satisfy all conditions.

  When the `:pat` options is used, `:tag`, `:id` and `:class` will
  be ignored.


  ### Examples:

      iex> e = div do
      ...>   span [id: "inner1", class: "inner"], "hello "
      ...>   span [id: "inner2", class: "inner"], "world"
      ...> end
      #div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
       #span<%{id: "inner2", class: "inner"} ["world"]>]>
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
  @spec select(enumerable) :: [t]
  def select(eml, opts \\ [])

  def select(content, opts) when is_list(content) do
    Enum.flat_map(content, &select(&1, opts))
  end

  def select(%Template{}, _opts), do: []

  def select(node, opts) do
    tag            = opts[:tag] || :any
    id             = opts[:id] || :any
    class          = opts[:class] || :any
    pat            = opts[:pat]
    select_parent? = opts[:parent] || false
    if select_parent? do
      if pat do
        pat_fun = fn node ->
          element?(node) and
          Enum.any?(node.content, fn el -> is_binary(el) and Regex.match?(pat, el) end)
        end
        Enum.filter(node, pat_fun)
      else
        idclass_fun = fn node ->
          element?(node) and
          Enum.any?(node.content, fn el -> Element.match?(el, tag, id, class) end)
        end
        Enum.filter(node, idclass_fun)
      end
    else
      if pat do
        pat_fun = fn
          node when is_binary(node) -> Regex.match?(pat, node)
          _                         -> false
        end
        Enum.filter(node, pat_fun)
      else
        Enum.filter(node, &Element.match?(&1, tag, id, class))
      end
    end
  end

  @doc """
  Adds content to matched elements.

  It traverses and returns the complete eml tree.
  Nodes are matched depending on the provided options.

  Those options can be:

  * `:tag` - match element by tag (`atom`)
  * `:id` - match element by id (`binary`)
  * `:class` - match element by class (`binary`)
  * `:at` -  add new content at begin or end of existing
    content, default is `:end` (`:begin | :end`)

  When `:tag`, `:id`, or `:class` are combined, only elements are
  selected that satisfy all conditions.


  ### Examples:

      iex> e = div do
      ...>   span [id: "inner1", class: "inner"], "hello "
      ...>   span [id: "inner2", class: "inner"], "world"
      ...> end
      #div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
       #span<%{id: "inner2", class: "inner"} ["world"]>]>
      iex> Eml.add(e, "dear ", id: "inner1")
      [#div<[#span<%{id: "inner1", class: "inner"} ["hello dear "]>,
        #span<%{id: "inner2", class: "inner"} ["world"]>]>]
      iex> Eml.add(e, "__", class: "inner", at: :begin)
      [#div<[#span<%{id: "inner1", class: "inner"} ["__hello "]>,
        #span<%{id: "inner2", class: "inner"} ["__world"]>]>]
      iex> Eml.add(e, span("!"), tag: :div) |> Eml.render!()
      "<div><span id='inner1' class='inner'>hello </span><span id='inner2' class='inner'>world</span><span>!</span></div>"

  """
  @spec add(transformable, Eml.Data.t, Keyword.t) :: transformable
  def add(eml, data, opts \\ []) do
    tag     = opts[:tag] || :any
    id      = opts[:id] || :any
    class   = opts[:class] || :any
    add_fun = fn node ->
      if element?(node) and Element.match?(node, tag, id, class),
        do:   Element.add(node, data, opts),
        else: node
    end
    transform(eml, add_fun)
  end

  @doc """
  Updates matched nodes.

  When nodes are matched, the provided function will be evaluated
  with the matched node as argument.

  When the provided function returns `nil`, the node will
  be removed from the eml tree. Any other returned value will be
  evaluated by `Eml.parse!/2` in order to guarantee valid eml.

  Nodes are matched depending on the provided options.

  Those options can be:

  * `:tag` - match element by tag (`atom`)
  * `:id` - match element by id (`binary`)
  * `:class` - match element by class (`binary`)
  * `:pat` - match binary content by regular expression (`RegEx.t`)
  * `:parent` - when set to true, selects the parent node
    of the matched node (`boolean`)

  When `:tag`, `:id`, or `:class` are combined, only elements are
  selected that satisfy all conditions.

  When the `:pat` options is used, `:tag`, `:id` and `:class` will
  be ignored.


  ### Examples:

      iex> e = div do
      ...>   span [id: "inner1", class: "inner"], "hello "
      ...>   span [id: "inner2", class: "inner"], "world"
      ...> end
      #div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
       #span<%{id: "inner2", class: "inner"} ["world"]>]>
      iex> Eml.update(e, fn m -> Element.id(m, "outer") end, tag: :div)
      [#div<%{id: "outer"}
       [#span<%{id: "inner1", class: "inner"} ["hello "]>,
        #span<%{id: "inner2", class: "inner"} ["world"]>]>]
      iex> Eml.update(e, fn m -> Element.id(m, "outer") end, id: "inner2", parent: true)
      [#div<%{id: "outer"}
       [#span<%{id: "inner1", class: "inner"} ["hello "]>,
        #span<%{id: "inner2", class: "inner"} ["world"]>]>]
      iex> Eml.update(e, fn s -> String.upcase(s) end, pat: ~r/.+/) |> Eml.render!()
      "<div><span id='inner1' class='inner'>HELLO </span><span id='inner2' class='inner'>WORLD</span></div>"

  """
  @spec update(transformable, (t -> Eml.Data.t), Keyword.t) :: transformable
  def update(eml, fun, opts \\ []) do
    tag            = opts[:tag] || :any
    id             = opts[:id] || :any
    class          = opts[:class] || :any
    pat            = opts[:pat]
    update_parent? = opts[:parent] || false
    update_fun     =
     if update_parent? do
       if pat do
          fn node ->
            if element?(node) and
            Enum.any?(node.content, fn el -> is_binary(el) and Regex.match?(pat, el) end),
              do: fun.(node),
            else: node
          end
        else
          fn node ->
            if element?(node) and
            Enum.any?(node.content, fn el -> Element.match?(el, tag, id, class) end),
              do: fun.(node),
            else: node
          end
        end
      else
        if pat do
          fn node ->
            if is_binary(node) and Regex.match?(pat, node),
             do: fun.(node),
           else: node
          end
        else
          fn node ->
            if Element.match?(node, tag, id, class),
              do: fun.(node),
            else: node
          end
        end
     end
    transform(eml, update_fun)
  end

  @doc """
  Removes matched nodes from the eml tree.

  See `update/3` for a description of the provided options.

  ### Examples:

      iex> e = div do
      ...>   span [id: "inner1", class: "inner"], "hello "
      ...>   span [id: "inner2", class: "inner"], "world"
      ...> end
      #div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
       #span<%{id: "inner2", class: "inner"} ["world"]>]>
      iex> Eml.remove(e, tag: :div)
      []
      iex> Eml.remove(e, id: "inner1")
      [#div<[#span<%{id: "inner2", class: "inner"} ["world"]>]>]
      iex> Eml.remove(e, pat: ~r/.*/)
      [#div<[#span<%{id: "inner1", class: "inner"}>,
        #span<%{id: "inner2", class: "inner"}>]>]

  """
  @spec remove(transformable, Keyword.t) :: transformable
  def remove(eml, opts \\ []) do
    tag            = opts[:tag] || :any
    id             = opts[:id] || :any
    class          = opts[:class] || :any
    pat            = opts[:pat]
    remove_parent? = opts[:parent] || false
    remove_fun     =
      if remove_parent? do
        if pat do
          fn node ->
            if element?(node) and
            Enum.any?(node.content, fn el -> is_binary(el) and Regex.match?(pat, el) end),
              do: nil,
            else: node
          end
        else
          fn node ->
            if element?(node) and
            Enum.any?(node.content, fn el -> Element.match?(el, tag, id, class) end),
              do: nil,
            else: node
          end
        end
      else
        if pat do
          fn node ->
            if is_binary(node) and Regex.match?(pat, node),
             do: nil,
           else: node
          end
        else
          fn node ->
            if Element.match?(node, tag, id, class),
              do: nil,
            else: node
          end
        end
    end
    transform(eml, remove_fun)
  end

  @doc """
  Returns true if there's at least one node matches
  the provided options, returns false otherwise.

  In other words, returns true when the same select query
  would return a non-empty list.

  See `select/3` for a description of the provided options.

  ### Examples:

      iex> e = div do
      ...>   span [id: "inner1", class: "inner"], "hello "
      ...>   span [id: "inner2", class: "inner"], "world"
      ...> end
      #div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
       #span<%{id: "inner2", class: "inner"} ["world"]>]>
      iex> Eml.member?(e, id: "inner1")
      true
      iex> Eml.member?(e, class: "inner", id: "test")
      false
      iex> Eml.member?(e, pat: ~r/h.*o/)
      true

  """
  @spec member?(enumerable, Keyword.t) :: boolean
  def member?(eml, opts) do
    case select(eml, opts) do
      [] -> false
      _  -> true
    end
  end

  @doc """
  Recursively transforms `eml` content.

  This is the most low level operation provided by Eml for manipulating
  eml nodes. For example, `update/3` and `remove/2` are implemented by
  using this function.

  It accepts any eml and traverses all nodes of the provided eml tree.
  The provided transform function will be evaluated for every node `transform/3`
  encounters. Parent nodes will be transformed before their children. Child nodes
  of a parent will be evaluated before moving to the next sibling.

  When the provided function returns `nil`, the node will
  be removed from the eml tree. Any other returned value will be
  evaluated by `Eml.parse!/2` in order to guarantee valid eml.

  Note that because parent nodes are evaluated before their children,
  no children will be evaluated if the parent is removed.

  ### Examples:

      iex> e = div do
      ...>   span [id: "inner1", class: "inner"], "hello "
      ...>   span [id: "inner2", class: "inner"], "world"
      ...> end
      #div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
       #span<%{id: "inner2", class: "inner"} ["world"]>]>
      iex> Eml.transform(e, fn x -> if Element.has?(x, tag: :span), do: "matched", else: x end)
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
  @spec transform(transformable, (t -> Eml.Data.t)) :: transformable | nil
  def transform(eml, fun)

  def transform(eml, fun) when is_list(eml) do
    for node <- eml, t = transform(node, fun), do: t
  end

  def transform(node, fun) do
    case node |> fun.() |> Data.to_eml() do
      { :error, _ } -> nil
      node ->
        if element?(node),
          do: %Element{node| content: transform(node.content, fun)},
        else: node
    end
  end

  @doc """
  Parses data and converts it to eml

  How the data is interpreted depends on the `lang` argument.
  The default value is `Eml.Language.HTML', which means that
  strings are parsed as html.

  ### Examples:

      iex> Eml.parse("<body><h1 id='main-title'>The title</h1></body>")
      [#body<[#h1<%{id: "main-title"} ["The title"]>]>]

  """
  @spec parse(Eml.Data.t, lang) :: { :ok, t | [t] } | error
  def parse(data, lang \\ @default_lang) do
    case lang.parse(data) do
      { :error, e } ->
        { :error, e }
      [res] ->
        if is_list(data) do
          { :ok, [res] }
        else
          { :ok, res }
        end
      [] ->
        if is_list(data) do
          { :ok, [] }
        else
          { :ok, "" }
        end
      list when is_list(list) ->
        { :ok, list }
    end
  end

  @doc """
  Same as `Eml.parse/2`, except that it raises an exception, instead of returning an
  error tuple in case of an error.
  """
  @spec parse!(Eml.Data.t, lang) :: t | [t]
  def parse!(data, lang \\ @default_lang) do
    case parse(data, lang) do
      { :error, e } ->
        raise ArgumentError, message: "Error #{inspect e}"
      { :ok, eml } ->
        eml
    end
  end

  @doc false
  @spec to_content(Eml.Data.t | error, [t], atom) :: t | [t]
  def to_content(data, acc \\ [], at \\ :begin)

  # No-ops
  def to_content(nondata, acc, _)
  when nondata in [nil, "", []], do: acc

  # Handle lists
  def to_content(data, acc, :end)
  when is_list(data), do: add_nodes(data, :lists.reverse(acc), :end) |> :lists.reverse()
  def to_content(data, acc, :begin)
  when is_list(data), do: add_nodes(:lists.reverse(data), acc, :begin)

  # Convert data to eml node
  def to_content(data, acc, mode) do
    Data.to_eml(data) |> add_node(acc, mode)
  end

  defp add_node(node, [], _), do: [node]
  defp add_node(node, [h | t], :end) do
    if is_binary(node) and is_binary(h) do
      [h <> node | t]
    else
      [node, h | t]
    end
  end
  defp add_node(node, [h | t], :begin) do
    if is_binary(node) and is_binary(h) do
      [node <> h | t]
    else
      [node, h | t]
    end
  end

  defp add_nodes([h | t], acc, mode) do
    acc = if is_list(h) and mode === :end do
            add_nodes(h, acc, mode)
          else
            to_content(h, acc, mode)
          end
    add_nodes(t, acc, mode)
  end
  defp add_nodes([], acc, _), do: acc

  @doc """
  Renders eml content to the specified language, which is
  html by default.

  When the provided eml contains a template, you can bind
  its parameters by providing a Keyword list as the
  second argument where the keys are the parameter id's.

  The accepted options are:

  * `:lang` - The language to render to, by default `Eml.Language.HTML`
  * `:quote` - The type of quotes used for attribute values. Accepted values are `:single` (default) and `:double`.
  * `:escape` - Escape `&`, `<` and `>` in attribute values and content to HTML entities.
     Accepted values are `true` (default) and `false`.

  ### Examples:

      iex> Eml.render(body(h1([id: "main-title"], "A title")))
      {:ok, "<body><h1 id='main-title'>A title</h1></body>"}

      iex> Eml.render(body(h1([id: "main-title"], "A title")), quote: :double)
      {:ok, "<body><h1 id=\"main-title\">A title</h1></body>"}

      iex> Eml.render(p "Tom & Jerry")
      {:ok, "<p>Tom &amp; Jerry</p>"}

  """
  @spec render(t, Eml.Template.bindings, Keyword.t) :: { :ok, binary } | error
  def render(eml, bindings \\ [], opts \\ []) do
    { lang, opts } = Keyword.pop(opts, :lang, @default_lang)
    opts = Keyword.put(opts, :bindings, bindings)
    opts = Keyword.put(opts, :mode, :render)
    lang.render(eml, opts)
  end

  @doc """
  Same as `Eml.render/3`, except that it raises an exception, instead of returning an
  error tuple in case of an error.
  """
  @spec render!(t, Eml.Template.bindings, Keyword.t) :: binary
  def render!(eml, bindings \\ [], opts \\ []) do
    case render(eml, bindings, opts) do
      { :ok, str } ->
        str
      { :error, { :unbound_params, params } } ->
        raise ArgumentError, message: "Unbound parameters in template: #{inspect params}"
      { :error, e } ->
        raise ArgumentError, message: inspect(e, pretty: true)
    end
  end

  @doc """
  Same as `Eml.render/3` except that it doesn't return an error when
  not all parameters are bound and always returns a template.

  ### Examples:

      iex> t = Eml.compile(body(h1([id: "main-title"], :the_title)))
      { :ok, #Template<[:the_title]> }
      iex> Eml.render(t, bindings: [the_title: "The Title"])
      {:ok, "<body><h1 id='main-title'>The Title</h1></body>"}

  """
  @spec compile(t, Eml.Template.bindings, Keyword.t) :: { :ok, Eml.Template.t } | error
  def compile(eml, bindings \\ [], opts \\ []) do
    { lang, opts } = Keyword.pop(opts, :lang, @default_lang)
    opts = Keyword.put(opts, :bindings, bindings)
    opts = Keyword.put(opts, :mode, :compile)
    lang.render(eml, opts)
  end

  @doc """
  Same as `Eml.compile/3`, except that it raises an exception, instead of returning an
  error tuple in case of an error.
  """
  @spec compile!(t, Eml.Template.bindings, Keyword.t) :: Eml.Template.t
  def compile!(eml, bindings \\ [], opts \\ []) do
     case compile(eml, bindings, opts) do
       { :ok, str } ->
        str
      { :error, e } ->
        raise ArgumentError, message: inspect(e, pretty: true)
    end
  end

  @doc """
  Similar to `Eml.compile/3`, but returns a compiled EEx template, instead of an Eml template.
  """
  @spec compile_to_eex(t, Eml.Template.bindings, Keyword.t) :: { :ok, Macro.t } | error
  def compile_to_eex(eml, bindings \\ [], opts \\ []) do
    eex_opts = [engine: opts[:eex_engine] || EEx.SmartEngine]
    opts = Keyword.put_new(opts, :escape, false)
    case compile(eml, bindings, opts) do
      { :ok, res } ->
        { :ok, to_eex(res) |> EEx.compile_string(eex_opts) }
      { :error, e } ->
        { :error, e }
    end
  end

  @doc """
  Same as `Eml.compile_to_eex/3`, except that it raises an exception, instead of returning an
  error tuple in case of an error.
  """
  @spec compile_to_eex!(t, Eml.Template.bindings, Keyword.t) :: Macro.t
  def compile_to_eex!(eml, bindings \\ [], opts \\ []) do
    case compile_to_eex(eml, bindings, opts) do
      { :ok, res } ->
        res
      { :error, e } ->
        raise ArgumentError, message: inspect(e, pretty: true)
    end
  end

  @doc """
  Similar to `Eml.compile/3`, but returns an EEx template, instead of an Eml template.
  """
  @spec render_to_eex(t, Eml.Template.bindings, Keyword.t) :: { :ok, String.t } | error
  def render_to_eex(eml, bindings \\ [], opts \\ []) do
    opts = Keyword.put_new(opts, :escape, false)
    case compile(eml, bindings, opts) do
      { :ok, res } ->
        { :ok, to_eex(res) }
      { :error, e } ->
        { :error, e }
    end
  end

  @doc """
  Same as `Eml.render_to_eex/3`, except that it raises an exception, instead of returning an
  error tuple in case of an error.
  """
  @spec render_to_eex!(t, Eml.Template.bindings, Keyword.t) :: String.t
  def render_to_eex!(eml, bindings \\ [], opts \\ []) do
    case render_to_eex(eml, bindings, opts) do
      { :ok, res } ->
        res
      { :error, e } ->
        raise ArgumentError, message: inspect(e, pretty: true)
    end
  end

  defp to_eex(%Eml.Template{chunks: chunks}) do
    for c <- chunks, into: "" do
      case c do
        %Eml.Parameter{id: id} ->
          "<%= #{id} %>"
        _ ->
          c
      end
    end
  end

  @doc """
  Extracts a value from content (which is always a list) or an element

  ### Examples

      iex> Eml.unpack ["42"]
      "42"

      iex> Eml.unpack 42
      42

      iex> Eml.unpack(div "hallo")
      "hallo"

      iex> Eml.unpack Eml.unpack(div(span("hallo")))
      "hallo"

  """
  @spec unpack(t) :: t
  def unpack(%Element{content: [node]}), do: node
  def unpack(%Element{content: content}),   do: content
  def unpack([node]),                   do: node
  def unpack(eml),                         do: eml

  @doc """
  Extracts a value recursively from content or an element

  ### Examples

      iex> Eml.unpackr div(span(42))
      "42"

      iex> Eml.unpackr div([span("Hallo"), span(" world")])
      ["Hallo", " world"]

  """
  @spec unpackr(t) :: unpackr_result
  def unpackr(%Element{content: [node]}),   do: unpackr(node)
  def unpackr(%Element{content: content}),     do: unpack_content(content)
  def unpackr([node]),                     do: unpackr(node)
  def unpackr(content) when is_list(content), do: unpack_content(content)
  def unpackr(node),                       do: node

  defp unpack_content(content) do
    for node <- content, do: unpackr(node)
  end

  @doc """
  Extracts a value recursively from content or an element and flatten the results.
  """
  @spec funpackr(t) :: funpackr_result
  def funpackr(eml), do: unpackr(eml) |> :lists.flatten

  @doc "Checks if a term is a `Eml.Element` struct."
  @spec element?(term) :: boolean
  def element?(%Element{}), do: true
  def element?(_),   do: false

  @doc "Checks if a value is regarded as empty by Eml."
  @spec empty?(term) :: boolean
  def empty?(nil), do: true
  def empty?([]), do: true
  def empty?(%Element{content: []}), do: true
  def empty?(_), do: false

  @doc """
  Returns the type of content.

  The types are `:binary`, `:element`, `:template`, `:parameter`, or `:undefined`.
  """
  @spec type(t) :: :binary | :element | :template | :parameter | :undefined
  def type(bin) when is_binary(bin), do: :binary
  def type(%Element{}), do: :element
  def type(%Template{}), do: :template
  def type(%Eml.Parameter{}), do: :parameter
  def type(_), do: :undefined

  @doc false
  def default_alias_and_imports do
    quote do
      alias Eml.Element
      alias Eml.Template
      import Eml.Template, only: [bind: 2]
    end
  end
    
  # use Eml

  defmacro __using__(_) do
    quote do
      import Eml, only: [defeml: 2, defhtml: 2, precompile: 1, precompile: 2]
    end
  end
end
