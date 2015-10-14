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
  end |> Eml.compile
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

  @default_elements Eml.HTML
  @default_parser Eml.HTML.Parser

  @type t :: Eml.Encoder.t | [Eml.Encoder.t] | [t]
  @type node_primitive :: String.t | { :safe, String.t } | Macro.t | Eml.Element.t

  @doc """
  Define a template function that compiles eml to a string during compile time.

  Eml uses the assigns extension from `EEx` for parameterizing templates. See
  the `EEx` docs for more info about them. The function that the template macro
  defines accepts optionally any Dict compatible dictionary as argument for
  binding values to assigns.

  ### Example:

      iex> defmodule MyTemplates1 do
      ...>   use Eml
      ...>   use Eml.HTML
      ...>
      ...>   template example do
      ...>     div id: "example" do
      ...>       span @text
      ...>     end
      ...>   end
      ...> end
      iex> MyTemplates.example text: "Example text"
      {:safe, "<div id='example'><span>Example text</span></div>"}


  Eml templates provides two ways of executing logic during runtime. By
  providing assigns handlers to the optional `funs` dictionary, or by calling
  external functions during runtime with the `&` operator.

  ### Example:

      iex> defmodule MyTemplates2 do
      ...>   use Eml
      ...>   use Eml.HTML
      ...>
      ...>   template assigns_handler,
      ...>   text: &String.upcase/1 do
      ...>     div id: "example1" do
      ...>       span @text
      ...>     end
      ...>   end
      ...>
      ...>   template external_call do
      ...>     body &assigns_handler(text: @example_text)
      ...>   end
      ...> end
      iex> MyTemplates.assigns_handler text: "Example text"
      {:safe, "<div id='example'><span>EXAMPLE TEXT</span></div>"}
      iex> MyTemplates.exernal_call example_text: "Example text"
      {:safe, "<body><div id='example'><span>EXAMPLE TEXT</span></div></body>"}


  Templates are composable, so they are allowed to call other templates. The
  only catch is that it's not possible to pass an assign to another template
  during precompilation. The reason for this is that the logic in a template is
  executed the moment the template is called, so if you would pass an assign
  during precompilation, the logic in a template would receive this assign
  instead of its result, which is only available during runtime. This all means
  that when you for example want to pass an assign to a nested template, the
  template should be prefixed with the `&` operator, or in other words, executed
  during runtime.

  ### Example

      iex> defmodule T1 do
      ...>   template templ1,
      ...>   num: &(&1 + &1) do
      ...>     div @num
      ...>   end
      ...> end

      iex> template templ2 do
      ...>   h2 @title
      ...>   templ1(num: @number) # THIS GENERATES A COMPILE TIME ERROR
      ...>   &templ1(num: @number) # THIS IS OK
      ...> end

  Note that because the body of a template is evaluated at compiletime, it's
  not possible to call other functions from the same module without using `&`
  operator.

  Instead of defining a do block, you can also provide a path to a file with the
  `:file` option.

  ### Example:

      iex> File.write! "test.eml.exs", "div @number"
      iex> defmodule MyTemplates3 do
      ...>   use Eml
      ...>   use Eml.HTML
      ...>
      ...>   template from_file, file: "test.eml.exs"
      ...> end
      iex> File.rm! "test.eml.exs"
      iex> MyTemplates3.from_file number: 42
      {:safe, "<div>42</div>"}

  """
  defmacro template(name, funs \\ [], do_block) do
    do_template(name, funs, do_block, __CALLER__, false)
  end

  @doc """
  Define a private template.

  Same as `template/3` except that it defines a private function.
  """
  defmacro templatep(name, funs \\ [], do_block) do
    do_template(name, funs, do_block, __CALLER__, true)
  end

  defp do_template(tag, funs, do_block, caller, private) do
    { tag, _, _ } = tag
    def_call = if private, do: :defp, else: :def
    template = Eml.Compiler.precompile(caller, do_block)
    quote do
      unquote(def_call)(unquote(tag)(var!(assigns))) do
        _ = var!(assigns)
        var!(funs) = unquote(funs)
        _ = var!(funs)
        unquote(template)
      end
    end
  end

  @doc """
  Define a template as an anonymous function.

  Same as `template/3`, except that it defines an anonymous function.

  ### Example
      iex> t = template_fn names: fn names ->
      ...>   for n <- names, do: li n
      ...> end do
      ...>   ul @names
      ...> end
      iex> t.(names: ~w(john james jesse))
      {:safe, "<ul><li>john</li><li>james</li><li>jesse</li></ul>"}

  """
  defmacro template_fn(funs \\ [], do_block) do
    template = Eml.Compiler.precompile(__CALLER__, do_block)
    quote do
      fn var!(assigns) ->
        _ = var!(assigns)
        var!(funs) = unquote(funs)
        _ = var!(funs)
        unquote(template)
      end
    end
  end

  @doc """
  Define a component element

  Components in Eml are a special kind of element that inherit functionality
  from templates. Like templates, everything within the do block gets
  precompiled, except assigns and function calls prefixed with the `&`
  operator. Defined attributes on a component can be accessed as assigns, just
  like with templates. Content can be accessed via the the special assign
  `__CONTENT__`. However, since the type of a component is `Eml.Element.t`,
  they can be queried and transformed, just like normal Eml elements.

  See `template/3` for more info about composability, assigns, runtime logic and
  accepted options.

  ### Example

      iex> use Eml
      iex> use Eml.HTML
      iex> defmodule ElTest do
      ...>
      ...>   component my_list,
      ...>   __CONTENT__: fn content ->
      ...>     for item <- content do
      ...>       li do
      ...>         span "* "
      ...>         span item
      ...>         span " *"
      ...>       end
      ...>     end
      ...>   end do
      ...>     ul [class: @class], @__CONTENT__
      ...>   end
      ...>
      ...> end
      iex> import ElTest
      iex> el = my_list class: "some-class" do
      ...>   "Item 1"
      ...>   "Item 2"
      ...> end
      #my_list<%{class: "some-class"} ["Item 1", "Item 2"]>
      iex> Eml.compile(el)
      "<ul class='some-class'><li><span>* </span><span>Item 1</span><span> *</span></li><li><span>* </span><span>Item 2</span><span> *</span></li></ul>"
  """
  defmacro component(tag, funs \\ [], do_block) do
    do_template_element(tag, funs, do_block, __CALLER__, false)
  end

  @doc """
  Define a fragment element

  Fragments in Eml are a special kind of element that inherit functionality from
  templates. Like templates, everything within the do block gets precompiled,
  except assigns. Defined attributes on a component can be accessed as assigns,
  just like with templates. Content can be accessed via the the special assign
  `__CONTENT__`.  However, since the type of a fragment is `Eml.Element.t`, they
  can be queried and transformed, just like normal Eml elements.

  The difference between components and fragments is that fragments are without
  any logic, so assign handlers or the `&` operator are not allowed in a
  fragment definition.

  The reason for their existence is easier composability and performance,
  because unlike templates and components, it is allowed to pass assigns to
  fragments during precompilation. This is possible because fragments don't
  contain any logic.

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
      iex> Eml.compile page
      "<!doctype html>\n<html><head><meta charset='UTF-8'/><title>Hello!!</title></head><body><div>Hello World</div></body></html>"
  """
  defmacro fragment(tag, do_block) do
    do_template_element(tag, nil, do_block, __CALLER__, true)
  end

  defp do_template_element(tag, funs, do_block, caller, fragment?) do
    { tag, _, _ } = tag
    template = Eml.Compiler.precompile(caller, Keyword.merge(do_block, fragment: fragment?))
    template_tag = (Atom.to_string(tag) <> "__template") |> String.to_atom()
    template_type = if fragment?, do: :fragment, else: :component
    funs = unless fragment? do
      quote do
        var!(funs) = unquote(funs)
        _ = var!(funs)
      end
    end
    quote do
      @doc false
      def unquote(template_tag)(var!(assigns)) do
        _ = var!(assigns)
        unquote(funs)
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
  def parse(data, opts \\ [])

  def parse(data, opts) when is_binary(data) do
    parser = opts[:parser] || @default_parser
    parser.parse(data, opts)
  end
  def parse(data, _) do
    raise Eml.ParseError, message: "Bad argument: #{inspect data}"
  end

  @doc """
  Compiles eml content with the specified markup compiler, which is html by default.

  The accepted options are:

  * `:compiler` - The compiler to use, by default `Eml.HTML.Compiler`
  * `:quotes` - The type of quotes used for attribute values. Accepted values are `:single` (default) and `:double`.
  * `:transform` - A function that receives every node just before it get's compiled. Same as using `transform/2`,
     but more efficient, since it's getting called during the compile pass.
  * `:escape` - Automatically escape strings, default is `true`.

  In case of error, raises an Eml.CompileError exception.

  ### Examples:

      iex> Eml.compile(body(h1([id: "main-title"], "A title")))
      "<body><h1 id='main-title'>A title</h1></body>"

      iex> Eml.compile(body(h1([id: "main-title"], "A title")), quotes: :double)
      "<body><h1 id=\"main-title\">A title</h1></body>"

      iex> Eml.compile(p "Tom & Jerry")
      "<p>Tom &amp; Jerry</p>"

  """
  @spec compile(t, Dict.t) :: String.t
  def compile(content, opts \\ [])
  def compile({ :safe, string }, _opts) do
    string
  end
  def compile(content, opts) do
    case Eml.Compiler.compile(content, opts) do
      { :safe, string } ->
        string
      _ ->
        raise Eml.CompileError, message: "Bad argument: #{inspect content}"
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
  Import macro's from this module and alias `Eml.Element`.

  Accepts the following options:

  * `:compile` - Set dcompile options as a Keyword list for all templates,
    components and fragments that are defined in the module where `use Eml` is
    invoked. See `Eml.compile/2` for all available options.
  * `:elements` - Which elements to import in the current scope. Accepts a
    module, or list of modules and defaults to `Eml.HTML`. When you don't want
    to import any elements, set to `nil` or `false`.
  """
  defmacro __using__(opts) do
    use_elements = if mods = Keyword.get(opts, :elements, @default_elements) do
                 for mod <- List.wrap(mods) do
                   quote do: use unquote(mod)
                 end
               end
    compile_opts = Keyword.get(opts, :compile, [])
    if mod = __CALLER__.module do
      Module.put_attribute(mod, :eml_compile, compile_opts)
    end
    quote do
      unquote(use_elements)
      alias Eml.Element
      import Eml, only: [
        template: 2, template: 3,
        templatep: 2, templatep: 3,
        template_fn: 1, template_fn: 2,
        fragment: 2,
        component: 2, component: 3
      ]
    end
  end
end
