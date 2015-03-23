defmodule Eml do
  @moduledoc """
  Eml makes markup a first class citizen in Elixir. It provides a
  flexible and modular toolkit for generating, parsing and
  manipulating markup. It's main focus is html, but other markup
  languages could be implemented as well.

  To start off:

  This piece of code
  ```elixir
  use Eml.HTML

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
  end |> Eml.render
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

  The functions and macro's in the `Eml` module cover most of
  Eml's public API.
  """

  alias Eml.Element

  @default_compiler Eml.HTML.Compiler
  @default_parser Eml.HTML.Parser

  @type t :: Eml.Encoder.t | [Eml.Encoder.t] | [t]

  @doc """
  Define a template function that renders eml to a string during compile time.

  Quoted expressions are evaluated at runtime and it's results are compileed to
  eml and concatenated with the precompiled eml.

  Eml uses the assigns extension from `EEx` for easy data access in a
  template. See the `EEx` docs for more info about them. Since all runtime
  behaviour is written in quoted expressions, assigns need to be quoted too. To
  prevent you from writing things like `quote do: @my_assign + 4` all the time,
  Eml provides the `&` capture operator as a shortcut for `quote do: ...`. You
  can use this shortcut only in template and component macro's. This means that
  for example `div &(@a + 4)` and `div (quote do: @a + 4)` have the same result
  inside a template. If you just want to pass an assign, you can even leave out
  the capture operator and just write `div @a`. The function that the template
  macro defines accepts optionally any Dict compatible dictionary as argument
  for binding values to assigns.

  Templates are composable, so they are allowed to call other templates. The
  only catch is that it's not possible to pass a quoted expression to a
  template.  The reason for this is that the logic in a template is executed the
  moment the template is called, so if you would pass a quoted expression, the
  logic in a template would receive this quoted expression instead of its
  result. This all means that when you for example want to pass an assign to a
  nested template, the template should be part of a quoted expression, or in
  other word, executed during runtime.

  Note that because the unquoted code is evaluated at compile time, it's not
  possible to call other functions from the same module. Quoted expressions
  however can call any local function, including other templates.

  Instead of defining a do block, you can also provide a path to a file with the
  `:file` option.

  In addition, all options of `Eml.render/3` also apply to the template macro.

  ### Example:

      iex> File.write! "test.eml.exs", "div(quote do: @number + @number)"
      iex> defmodule MyTemplates do
      ...>   use Eml
      ...>   use Eml.HTML
      ...>
      ...>   template fruit do
      ...>     prefix = "fruit"
      ...>     div do
      ...>       span [class: "prefix"], prefix
      ...>       span [class: "name"], &@name
      ...>     end
      ...>   end
      ...>
      ...>   template tropical_fruit do
      ...>     body do
      ...>       h2 "Tropical Fruit"
      ...>       quote do
      ...>         for n <- @names do
      ...>           fruit name: n
      ...>         end
      ...>       end
      ...>     end
      ...>   end
      ...>
      ...>   template from_file, file: "test.eml.exs"
      ...> end
      iex> File.rm! "test.eml.exs"
      iex> MyTemplates.tropical_fruit names: ~w(mango papaya banana acai)
      "<body><h2>Tropical Fruit</h2><div><span class='prefix'>fruit</span><span class='name'>mango</span></div><div><span class='prefix'>fruit</span><span class='name'>papaya</span></div><div><span class='prefix'>fruit</span><span class='name'>banana</span></div><div><span class='prefix'>fruit</span><span class='name'>acai</span></div></body>"
      iex> MyTemplates.from_file number: 21
      "<div>42</div>"
      iex> MyTemplates.precompile()
      "<body><p>Strawberry</p></body>"

  """
  defmacro template(name, opts, do_block \\ []) do
    do_template(name, opts, do_block, __CALLER__, false)
  end

  @doc """
  Define a private template.

  Same as `template/3` except that it defines a private function.
  """
  defmacro templatep(name, opts, do_block \\ []) do
    do_template(name, opts, do_block, __CALLER__, true)
  end

  defp do_template(tag, opts, do_block, caller, private) do
    opts = Keyword.merge(opts, do_block)
    { tag, _, _ } = tag
    def_call = if private, do: :defp, else: :def
    template = Eml.Compiler.precompile(caller, opts)
    quote do
      unquote(def_call)(unquote(tag)(var!(assigns))) do
        _ = var!(assigns)
        unquote(template)
      end
    end
  end

  @doc """
  Define a template as an anonymous function.

  All non quoted expressions are precompiled and the anonymous function that is
  returned expects a Keyword list for binding assigns.

  See `template/3` for more info.

  ### Example
      iex> t = template_fn do
      ...>   names = quote do
      ...>     for n <- @names, do: li n
      ...>   end
      ...>   ul names
      ...> end
      iex> t.(names: ~w(john james jesse))
      "<ul><li>john</li><li>james</li><li>jesse</li></ul>"

  """
  defmacro template_fn(opts, do_block \\ []) do
    opts = Keyword.merge(opts, do_block)
    template = Eml.Compiler.precompile(__CALLER__, opts)
    quote do
      fn var!(assigns) ->
        _ = var!(assigns)
        unquote(template)
      end
    end
  end

  @doc """
  Define a component macro

  Components in Eml are a special kind of element that inherit functionality
  from templates. Like templates, everything within the do block gets
  precompiled, except quoted code. Defined attributes on a component can be
  accessed as assigns, just like with templates. Content can be accessed via the
  the special assign `__CONTENT__`.  However, since the type of a component is
  `Eml.Element.t`, they can be queried and transformed, just like normal Eml
  elements.

  See `template/3` for more info about composability, quoted blocks, assigns and
  accepted options.

  ### Example

      iex> use Eml
      nil
      iex> use Eml.HTML
      nil
      iex> defmodule ElTest do
      ...>
      ...>   component my_list do
      ...>     ul class: &@class do
      ...>       quote do
      ...>         for item <- @__CONTENT__ do
      ...>           li do
      ...>             span "* "
      ...>             span item
      ...>             span " *"
      ...>           end
      ...>         end
      ...>       end
      ...>     end
      ...>   end
      ...>
      ...> end
      {:module, ElTest, ...}
      iex> import ElTest
      nil
      iex> el = my_list class: "some-class" do
      ...>   "Item 1"
      ...>   "Item 2"
      ...> end
      #my_list<%{class: "some-class"} ["Item 1", "Item 2"]>
      iex> Eml.render(el)
      "<ul class='some-class'><li><span>* </span><span>Item 1</span><span> *</span></li><li><span>* </span><span>Item 2</span><span> *</span></li></ul>"
  """
  defmacro component(tag, opts, do_block \\ []) do
    do_template_element(tag, opts, do_block, __CALLER__)
  end

  @doc """
  Define a fragment macro

  Fragments in Eml are a special kind of element that inherit functionality
  from templates. Like templates, everything within the do block gets
  precompiled, except assigns. Defined attributes on a component can be
  accessed as assigns, just like with templates. Content can be accessed via the
  the special assign `__CONTENT__`.  However, since the type of a component is
  `Eml.Element.t`, they can be queried and transformed, just like normal Eml
  elements.

  The difference between components and fragments is that fragments are
  without any logic, so quoted expressions or the `&` capture operator are not
  allowed in a fragment definition. This means that assigns don't need to be
  quoted.

  The reason for their existence is easier composability and performance,
  because unlike templates and components, it is allowed to pass quoted
  expressions to fragments.  This is possible because fragments don't contain
  any logic.

  See `render/3` for more info about accepted options.

  ### Example

      iex> use Eml
      nil
      iex> use Eml.HTML
      nil
      iex> defmodule ElTest do
      ...>
      ...>   fragment basic_page do
      ...>     html do
      ...>       head do
      ...>         meta charset: "UTF-8"
      ...>         title @title
      ...>       end
      ...>       body do
      ...>         @__CONTENT__
      ...>       end
      ...>     end
      ...>   end
      ...>
      ...> end
      {:module, ElTest, ...}
      iex> import ElTest
      nil
      iex> page = basic_page title: "Hello!" do
      ...>   div "Hello World"
      ...> end
      #basic_page<%{title: "Hello!!"} [#div<"Hello World">]>
      iex> Eml.render page
      "<!doctype html>\n<html><head><meta charset='UTF-8'/><title>Hello!!</title></head><body><div>Hello World</div></body></html>"
  """
  defmacro fragment(tag, opts, do_block \\ []) do
    opts = Keyword.put(opts, :fragment, true)
    do_template_element(tag, opts, do_block, __CALLER__)
  end

  defp do_template_element(tag, opts, do_block, caller) do
    opts = Keyword.merge(opts, do_block)
    { tag, _, _ } = tag
    template = Eml.Compiler.precompile(caller, opts)
    template_tag = (Atom.to_string(tag) <> "__template") |> String.to_atom()
    template_type = if opts[:fragment], do: :fragment, else: :component
    quote do
      @doc false
      def unquote(template_tag)(var!(assigns)) do
        _ = var!(assigns)
        unquote(template)
      end
      defmacro unquote(tag)(content_or_attrs, maybe_content \\ nil) do
        tag = unquote(tag)
        template_tag = unquote(template_tag)
        template_type = unquote(template_type)
        in_match = Macro.Env.in_match?(__CALLER__)
        { attrs, content } = Eml.Element.Generator.extract_content(content_or_attrs, maybe_content, in_match)
        if in_match do
          quote do
            %Eml.Element{tag: unquote(tag), attrs: unquote(attrs), content: unquote(content)}
          end
        else
          quote do
            %Eml.Element{tag: unquote(tag),
                         attrs: Enum.into(unquote(attrs), %{}),
                         content: List.wrap(unquote(content)),
                         template: &unquote(__MODULE__).unquote(template_tag)/1,
                         type: unquote(template_type)}
          end
        end
      end
    end
  end

  defp collect_embeded_decoders(ast, _env) do
    { match, decoders } = Macro.prewalk(ast, [], fn
      { :decode, _ , _ } = decode, acc ->
        decode = Macro.expand_once(decode, __ENV__)
        { as, decode } = Keyword.pop(decode, :as)
        decode = Keyword.put(decode, :from, as)
        { as, [decode | acc] }
      expr, acc ->
        { expr, acc }
    end)
    exprs = for d <- decoders do
      quote do
        { :ok, unquote(d[:from]) } = Eml.decode(unquote(d))
      end
    end
    { match, { :__block__, [], exprs } }
  end

  defmacro decode(opts, do_block \\ []) do
    opts = Keyword.merge(opts, do_block)
    if opts[:as] do
      opts
    else
      { match, decoders } = collect_embeded_decoders(opts[:do], __CALLER__)
      quote do
        try do
          from = unquote(opts[:from])
          by   = unquote(opts[:by])
          if is_list(from) do
            res = for node <- from do
              Eml.do_match(node, unquote(opts[:select]), by, unquote(match), unquote(decoders))
            end
            { :ok, res }
          else
            { :ok, Eml.do_match(from, unquote(opts[:select]), by, unquote(match), unquote(decoders)) }
          end
        rescue
          MatchError ->
            { :error, :nomatch }
        end
      end
    end
  end

  defmacro decoder(opts, do_block \\ []) do
    opts = Keyword.merge(opts, do_block)
    name = opts[:name] || :decoder
    quote do
      def unquote(name)(eml) do
        Eml.decode(from: eml, select: unquote(opts[:select]), by: unquote(opts[:by]), do: unquote(opts[:do]))
      end
    end
  end

  @doc false
  defmacro do_match(eml, select, by, match, decoders) do
    quote do
      eml = unquote(eml)
      by  = unquote(by)
      if is_function(by) or (is_atom(by) and not is_nil(by)) do
        decoder = if is_function(by) do
                    by
                  else
                    &by.decoder/1
                  end
        { :ok, res } = decoder.(eml)
        res
      else
        unquote(match) = eml
        unquote(decoders)
        unquote(select)
      end
    end
  end

  @doc """
  Parses data and converts it to eml

  How the data is interpreted depends on the `parser` argument.
  The default value is `Eml.HTML.Parser', which means that
  strings are parsed as html.

  In case of error, raises an Eml.ParseError exception.

  ### Examples:

      iex> Eml.parse("<body><h1 id='main-title'>The title</h1></body>")
      [#body<[#h1<%{id: "main-title"} "The title">]>]
  """
  @spec parse(String.t, module) :: [t]
  def parse(data, parser \\ @default_parser)

  def parse(data, parser) when is_binary(data) do
    parser.parse(data)
  end
  def parse(data, _) do
    raise Eml.ParseError, type: :badarg, value: data
  end

  @doc """
  Renders eml content with the specified markup compiler, which is html by default.

  When the provided eml contains quoted expressions that use assigns,
  you can bind to these by providing a Keyword list as the
  second argument.

  The accepted options are:

  * `:compiler` - The compiler to use, by default `Eml.HTML.Compiler`
  * `:quotes` - The type of quotes used for attribute values. Accepted values are `:single` (default) and `:double`.
  * `:transform` - A function that receives every node just before it get's compiled. Same as using `transform/2`,
     but more efficient, since it's getting called during the compile pass.
  * `:escape` - Automatically escape strings, default is `true`.

  In case of error, raises an Eml.CompileError exception.

  ### Examples:

      iex> Eml.render(body(h1([id: "main-title"], "A title")))
      "<body><h1 id='main-title'>A title</h1></body>"

      iex> Eml.render(body(h1([id: "main-title"], "A title")), quotes: :double)
      "<body><h1 id=\"main-title\">A title</h1></body>"

      iex> Eml.render(p "Tom & Jerry")
      "<p>Tom &amp; Jerry</p>"

  """
  @spec render(t, Dict.t, Dict.t) :: String.t
  def render(content, assigns \\ %{}, opts \\ [])
  def render({ :safe, string }, assigns, opts) when is_binary(string) do
    string
  end
  def render(content, assigns, opts) do
    case Eml.Compiler.compile(content, Keyword.put(opts, :fragment, false)) do
      { :safe, string } when is_binary(string) ->
        string
      quoted ->
        { { :safe, res }, _ } = Code.eval_quoted(quoted, [assigns: assigns])
        res
    end
  end

  @doc """
  Recursively transforms `eml` content.

  It traverses all nodes of the provided eml tree.  The provided transform
  function will be evaluated for every node `transform/3` encounters. Parent
  nodes will be transformed before their children. Child nodes of a parent will
  be evaluated before moving to the next sibling.

  When the provided function returns `nil`, the node will be removed from the
  eml tree.

  Note that because parent nodes are evaluated before their children, no
  children will be evaluated if the parent is removed.

  ### Examples:

      iex> e = div do
      ...>   span [id: "inner1", class: "inner"], "hello "
      ...>   span [id: "inner2", class: "inner"], "world"
      ...> end
      #div<[#span<%{id: "inner1", class: "inner"} "hello ">,
       #span<%{id: "inner2", class: "inner"} "world">]>

      iex> Eml.transform(e, fn
      ...>   span(_) -> "matched"
      ...>   node    -> node
      ...> end)
      #div<["matched", "matched"]>

      iex> transform(e, fn node ->
      ...>   IO.inspect(node)
      ...>   node
      ...> end)
      #div<[#span<%{class: "inner", id: "inner1"} "hello ">,
       #span<%{class: "inner", id: "inner2"} "world">]>
      #span<%{class: "inner", id: "inner1"} "hello ">
      "hello "
      #span<%{class: "inner", id: "inner2"} "world">
      "world"
      #div<[#span<%{class: "inner", id: "inner1"} "hello ">,
       #span<%{class: "inner", id: "inner2"} "world">]>
  """
  @spec transform(t, (t -> t)) :: t | nil
  def transform(nil, _fun) do
    nil
  end
  def transform(eml, fun) when is_list(eml) do
    for node <- eml, t = transform(node, fun), do: t
  end
  def transform(node, fun) do
    case fun.(node) do
      %Element{content: content} = node ->
        %Element{node| content: transform(content, fun)}
      node ->
        node
    end
  end

  @doc """
  Match on element tag, attributes, or content

  Implemented as a macro.
  ### Examples:

      iex> use Eml
      iex> use Eml.HTML
      iex> node = section [id: "my-section"], [div([id: "some_id"], "Some content"), div([id: "another_id"], "Other content")]
      iex> Eml.match?(node, attrs: %{id: "my-section"})
      true
      iex> Eml.match?(node, tag: :div)
      false
      iex> Enum.filter(node, &Eml.match?(&1, tag: :div))
      [#div<%{id: "some_id"} "Some content">, #div<%{id: "another_id"}
      "Other content">]
      iex> Eml.transform(node, fn node ->
      ...>   if Eml.match?(node, content: "Other content") do
      ...>     put_in(node.content, "New content")
      ...>   else
      ...>     node
      ...>   end
      ...> end)
      #section<%{id: "my-section"}
      [#div<%{id: "some_id"} "Some content">, #div<%{id: "another_id"}
       "New content">]>
  """
  defmacro match?(node, opts \\ []) do
    tag     = opts[:tag]     || quote do: _
    attrs   = opts[:attrs]   || quote do: _
    content = opts[:content] || quote do: _
    quote do
      case unquote(node) do
        %Eml.Element{tag: unquote(tag), attrs: unquote(attrs), content: unquote(content)} ->
          true
        _ ->
          false
      end
    end
  end

  @doc """
  Extracts a value recursively from content

  ### Examples

      iex> Eml.unpack [42]
     bm 42

      iex> Eml.unpack 42
      42

      iex> Eml.unpack(div "hallo")
      "hallo"

      iex> Eml.unpack Eml.unpack(div(span("hallo")))
      "hallo"

      iex> Eml.unpack div(span(42))
      42

      iex> Eml.unpack div([span("Hallo"), span(" world")])
      ["Hallo", " world"]

  """
  @spec unpack(t) :: t
  def unpack(%Element{content: content}) do
    unpack(content)
  end
  def unpack([node]) do
    unpack(node)
  end
  def unpack(content) when is_list(content) do
    for node <- content, do: unpack(node)
  end
  def unpack({ :safe, node }) do
    node
  end
  def unpack(node) do
    node
  end

  @doc """
  Escape content

  ### Examples

      iex> escape "Tom & Jerry"
      "Tom &amp; Jerry"
      iex> escape div span("Tom & Jerry")
      #div<[#span<["Tom &amp; Jerry"]>]>
  """
  @spec escape(t) :: t
  defdelegate escape(eml), to: Eml.Compiler

  @doc """
  Unescape content

  ### Examples

      iex> unescape "Tom &amp; Jerry"
      "Tom & Jerry"
      iex> unescape div span("Tom &amp; Jerry")
      #div<[#span<["Tom & Jerry"]>]>
  """
  @spec unescape(t) :: t
  defdelegate unescape(eml), to: Eml.Parser

  # use Eml
  @doc """
  Import macro's and alias core modules.

  Invoking it translates to:
  ```
  alias Eml.Element
  import Eml, only: [
    template: 2, template: 3,
    templatep: 2, templatep: 3,
    template_fn: 1, template_fn: 2,
    fragment: 2, fragment: 3,
    component: 2, component: 3,
    decoder: 1, decoder: 2
  ]
  ```
  """
  defmacro __using__(_) do
    quote do
      alias Eml.Element
      import Eml, only: [
        template: 2, template: 3,
        templatep: 2, templatep: 3,
        template_fn: 1, template_fn: 2,
        fragment: 2, fragment: 3,
        component: 2, component: 3,
        decoder: 1, decoder: 2
      ]
    end
  end
end
