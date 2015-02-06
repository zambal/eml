[![Build Status](https://api.travis-ci.org/zambal/eml.svg?branch=master)](https://travis-ci.org/zambal/eml)

# Eml

## Markup for developers

### What is it?
Eml makes markup a first class citizen in Elixir. It provides a
flexible and modular toolkit for generating, parsing and
manipulating markup. It's main focus is html, but other markup
languages could be implemented as well.

To start off:

This piece of code
```elixir
use Eml.HTML.Elements

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

### Why?
Most templating libraries are build around the idea of interpreting strings
that can contain embeded code. This code is mostly used for implementing view
logic in the template. You could say that these libraries are making code a first
class citizen in template strings. As long as the view logic is simple this works
pretty well, but with more complex views this can become quite messy. Eml takes
this idea inside out and makes the markup that you normally would write as a string
a first class citizen of the programming language, allowing you to organize view
logic with all the power of Elixir.

Please read on for a walkthrough that tries to cover most of Eml's features.


### Walkthrough

- [Intro](#intro)
- [Rendering](#rendering)
- [Parsing](#parsing)
- [Compiling and templates](#compiling-and-templates)
- [Unpacking](#unpacking)
- [Querying eml](#querying-eml)
- [Transforming eml](#transforming-eml)
- [Encoding data in Eml](#encoding-data-in-eml)
- [Notes](#notes)

#### Intro

```elixir
iex> use Eml
nil
iex> use Eml.HTML.Elements
nil
```

By invoking `use Eml`, some macro's are imported into the current scope
and the `Eml.Element` module is aliased. `use Eml.HTML.Elements` imports all
generated html element macros from `Eml.HTML.Elements` into the current scope.
The element macro's just translate to a call to `Eml.Element.new`, except when
used as a pattern in a match operation. When used inside a match, the macro
will be translated to %Eml.Element{...}. The nodes of an element can be
`String.t`, `Eml.Element.t`, `{ :quoted, Macro.t }` and `{ :safe, String.t }`.
We'll focus on strings and elements for now.
```elixir
iex> div 42
#div<["42"]>
```
Here we created a `div` element with `"42"` as it contents. Since Eml content's
only primitive data type are strings, the integer automatically gets converted.

The element macro's in Eml try to be clever about the type of arguments that
get passed. For example, if the first argument is a Keyword list, it will be
interpreted as attributes, otherwise as content.
```elixir
iex> div id: "some-id"
#div<%{id: "some-id"}>

iex> div "some content"
#div<["some content"]>

iex> div do
...>   "some content"
...> end
#div<["some content"]>

iex> div [id: "some-id"], "some content"
#div<%{id: "some-id"} ["some content"]>

iex> div id: "some-id" do
...>   "some content"
...> end
#div<%{id: "some-id"} ["some content"]>
```

Note that attributes are stored internally as a map and
that content is always wrapped in a list.


#### Rendering

Contents can be rendered to a string by calling `Eml.render`.
Eml automatically inserts a doctype declaration when the html
element is the root.
```elixir
iex> html(body(div(42))) |> Eml.render
{:safe, "<!doctype html>\n<html><body><div>42</div></body>\n</html>"}

iex> "text & more" |> div |> body |> html |> Eml.render
{:safe, "<!doctype html>\n<html><body><div>text &amp; more</div></body></html>"}
```
As you can see, you can also use Elixir's pipe operator for creating markup.
However, using do blocks, as can be seen in the introductory example,
is more convenient most of the time. By default, Eml also escapes `&`, `'`, `"`,
`<` and `>` characters in content or attribute values. `Eml.render` returns its 
results in a { :safe, ... } tuple indicating that the string is safe to insert as
content in other elementsHowever, it is possible to turn of auto escaping when 
rendering eml.

iex> Eml.render(div("Tom & Jerry"), [], safe: false)
"<div>Tom & Jerry</div>"

#### Parsing

Eml's parser by default converts a string with html content into Eml content.
```elixir
iex> Eml.parse "<!doctype html>\n<html><head><meta charset='UTF-8'></head><body><div>42</div></body></html>"
[#html<[#head<[#meta<%{charset: "UTF-8"}>]>, #body<[#div<["42"]>]>]>]

iex> Eml.parse "<div class=\"content article\"><h1 class='title'>Title<h1><p class=\"paragraph\">blah &amp; blah</p></div>"
[#div<%{class: ["content", "article"]}
 [#h1<%{class: "title"}
  ["Title", #h1<[#p<%{class: "paragraph"} ["blah & blah"]>]>]>]>]
```

The html parser is primarily written to parse html rendered by Eml, but it's
flexible enough to parse most html you throw at it. Most notable missing features
of the parser are attribute values without quotes and elements that are not properly
closed.


#### Compiling and templates

Compiling and templates can be used in situations where most content
is static and performance is critical. A template is just Eml content
that contains quoted expressions. `Eml.compile` precompiles all non quoted expressions.
All quoted expressions are evaluated at runtime and it's results are
rendered to eml and concatenated with the precompiled eml. You can use `Eml.render`
to render the compiled template to markup. It's not needed to work with `Eml.compile`
directly as using `Eml.template` and `Eml.template_fn` is more convenient in most cases.
`Eml.template` defines a function that has all non quoted expressions prerendered and
when called, concatenates the results from the quoted  expressions with it.
`Eml.template_fn` works the same, but returns an anonymous function instead.

Eml uses the assigns extension from `EEx` for easy data access in
a template. See the `EEx` docs for more info about them. Since all
runtime behaviour is written in quoted expressions, assigns need to
be quoted too. To prevent you from writing `quote do: @my_assign` all
the time, atoms can be used as a shortcut. This means that for example
`div(:a)` and `div(quote do: @a)` have the same result. This convertion
is being performed by the `Eml.Data` protocol. The function that the
template macro defines accepts optionally an Keyword list for binding
values to assigns.
```elixir
iex> e = h1 [:atoms, " ", :are, " ", :converted, " ", :to_assigns]
#h1<[{:quoted,
  {:@, [context: Eml.Data.Atom, import: Kernel],
   [{:atoms, [], Eml.Data.Atom}]}}, " ",
 {:quoted,
  {:@, [context: Eml.Data.Atom, import: Kernel], [{:are, [], Eml.Data.Atom}]}},
 " ",
 {:quoted,
  {:@, [context: Eml.Data.Atom, import: Kernel],
   [{:converted, [], Eml.Data.Atom}]}}, " ",
 {:quoted,
  {:@, [context: Eml.Data.Atom, import: Kernel],
   [{:to_assigns, [], Eml.Data.Atom}]}}]>
iex> t = Eml.compile(e)
{:quoted,
 {:safe,
  {:<>, ...}
iex> Eml.render(t, atoms: "Atoms", are: "are", converted: "converted", to_assigns: "to assigns.")
{ :safe, "<h1>Atoms are converted to assigns.</h1>" }

iex> e = ul(quote do
...>   for n <- @names, do: li n
...> end)
#ul<[quoted: {:for, [],
  [{:<-, [],
    [{:n, [], Elixir},
     {:@, [context: Elixir, import: Kernel], [{:names, [], Elixir}]}]},
   [do: {:li, [context: Elixir, import: Eml.HTML.Elements],
     [{:n, [], Elixir}]}]]}]>
# You can also call `Eml.render` directly, as it precompiles content too when needed
iex> Eml.render e, names: ~w(john james jesse)
{:safe, "<ul><li>john</li><li>james</li><li>jesse</li></ul>"}

iex> t = template_fn do
...>   ul(quote do
...>     for n <- @names, do: li n
...>   end)
...> end
#Function<6.90072148/1 in :erl_eval.expr/5>
iex> t.(names: ~w(john james jesse))
{:safe, "<ul><li>john</li><li>james</li><li>jesse</li></ul>"}
```
To bind data to assigns in Eml, you can either compile eml data to a template
and use `Eml.render` to bind data to assigns, or you can directly `Eml.render`,
which also precompiles on the fly when needed. However, any performance benefits of
using templates is lost this way. See the documentation of `Eml.template` for more info
and examples about templates.

**WARNING**

Since unquoted expressions in a template are evaluated during compile time, you can't call
functions or macro's from the same module, since the module isn't compiled yet. Also
you can't reliably call functions or macro's from other modules in the same project as
they might still not be compiled. Calling functions or macro's from dependencies should
work, as Elixir always compiles dependencies before the project itself.

Quoted expressions however have normal access to other functions, because they are evaluated
at runtime.

#### Unpacking

Since the contents of elements are always wrapped in a list, Eml provides
a utility function to easily access its contents.
```elixir
iex> Eml.unpack div 42
"42"
```
Eml also provides a recursive version called `unpackr`.
```elixir
iex> Eml.unpackr div span(42)
"42"
```


#### Querying eml

`Eml.Element` implements the Elixir `Enumerable` protocol for traversing a tree of
nodes. Let's start with creating something to query
```elixir
iex> e = html do
...>   head class: "head" do
...>     meta charset: "UTF-8"
...>   end
...>   body do
...>     article id: "main-content" do
...>       section class: ["intro", "article"] do
...>         h3 "Hello world"
...>       end
...>       section class: ["conclusion", "article"] do
...>         "TODO"
...>       end
...>     end
...>   end
...> end
#html<[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>,
 #body<[#article<%{id: "main-content"}
  [#section<%{class: ["intro", "article"]} [#h3<["Hello world"]>]>,
   #section<%{class: ["conclusion", "article"]} ["TODO"]>]>]>]>
```
To get an idea how the tree is traversed, first just print all nodes
```elixir
iex> Enum.each(e, fn x -> IO.puts(inspect x) end)
#html<[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>, #body<[#article<%{id: "main-content"} [#section<%{class: ["intro", "article"]} [#h3<["Hello world"]>]>, #section<%{class: ["conclusion", "article"]} ["TODO"]>]>]>]>
#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>
#meta<%{charset: "UTF-8"}>
#body<[#article<%{id: "main-content"} [#section<%{class: ["intro", "article"]} [#h3<["Hello world"]>]>, #section<%{class: ["conclusion", "article"]} ["TODO"]>]>]>
#article<%{id: "main-content"} [#section<%{class: ["intro", "article"]} [#h3<["Hello world"]>]>, #section<%{class: ["conclusion", "article"]} ["TODO"]>]>
#section<%{class: ["intro", "article"]} [#h3<["Hello world"]>]>
#h3<["Hello world"]>
"Hello world"
#section<%{class: ["conclusion", "article"]} ["TODO"]>
"TODO"
:ok
```

As you can see every node of the tree is passed to `Enum`.
Let's continue with some other examples
```elixir
iex> Enum.member?(e, "TODO")
true

iex> Enum.filter(e, &Element.has?(&1, tag: :h3))
[#h3<["Hello world"]>]

iex> Enum.filter(e, &Element.has?(&1, class: "article"))
[#section<%{class: ["intro", "article"]} [#h3<["Hello world"]>]>,
 #section<%{class: ["conclusion", "article"]} ["TODO"]>]

iex> Enum.filter(e, &Element.has?(&1, tag: :h3, class: "article"))
[]
```

Eml also provides the `Eml.select` and `Eml.member?` functions, which
can be used to select content and check for membership more easily.
Check the docs for more info about the options `Eml.select` accepts.
```elixir
iex> Eml.select(e, class: "article")
[#section<%{class: ["intro", "article"]} [#h3<["Hello world"]>]>,
 #section<%{class: ["conclusion", "article"]} ["TODO"]>]

# using `parent: true` instructs `Eml.select` to select the parent
# of the matched node(s)
iex> Eml.select(e, tag: :meta, parent: true)
[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>]

# when using the :pat option, a regular expression can be used to
# match binary content
iex> Eml.select(e, pat: ~r/H.*d/)
["Hello world"]

iex> Eml.select(e, pat: ~r/TOD/, parent: true)
[#section<%{class: ["conclusion", "article"]} ["TODO"]>]

iex> Eml.member?(e, class: "head")
true

iex> Eml.member?(e, tag: :article, class: "conclusion")
false
```


#### Transforming eml

Eml provides three high-level constructs for transforming eml: `Eml.update`,
`Eml.remove`, and `Eml.add`. Like `Eml.select` they traverse the complete
eml tree. Check the docs for more info about these functions. The following
examples work with the same eml snippet as in the previous section.

```elixir
iex> Eml.remove(e, class: "article")
#html<[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>,
 #body<[#article<%{id: "main-content"}>]>]>

iex> Eml.remove(e, pat: ~r/orld/)
#html<[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>,
 #body<[#article<%{id: "main-content"}
  [#section<%{class: ["intro", "article"]} [#h3<>]>,
   #section<%{class: ["conclusion", "article"]} ["TODO"]>]>]>]>

iex> Eml.update(e, &String.downcase(&1), pat: ~r/.*/)
#html<[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>,
 #body<[#article<%{id: "main-content"}
  [#section<%{class: ["intro", "article"]} [#h3<["hello world"]>]>,
   #section<%{class: ["conclusion", "article"]} ["todo"]>]>]>]>

iex> Eml.add(e, section([class: "pre-intro"], "...."), id: "main-content", at: :begin)
#html<[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>,
 #body<[#article<%{id: "main-content"}
  [#section<%{class: "pre-intro"} ["...."]>,
   #section<%{class: ["intro", "article"]} [#h3<["Hello world"]>]>,
   #section<%{class: ["conclusion", "article"]} ["TODO"]>]>]>]>

iex> Eml.add(e, section([class: "post-conclusion"], "...."), id: "main-content", at: :end)
#html<[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>,
 #body<[#article<%{id: "main-content"}
  [#section<%{class: ["intro", "article"]} [#h3<["Hello world"]>]>,
   #section<%{class: ["conclusion", "article"]} ["TODO"]>,
   #section<%{class: "post-conclusion"} ["...."]>]>]>]>
```

Eml also provides `Eml.transform`. All functions from the previous section are
implemented with it. `Eml.transform` mostly works like enumeration. The key
difference is that `Eml.transform` returns a modified version of the eml tree that
was passed as an argument, instead of collecting nodes in a list.
`Eml.transform` passes any node it encounters to the provided transformation
function. The transformation function can return any data that can be converted by the
`Eml.Data` protocol or `nil`, in which case the node is discarded, so it works a bit
like a map and filter function in one pass.
```elixir
iex> Eml.transform(e, fn x -> if Element.has?(x, class: "article"), do: Element.content(x, "#"), else: x end)
#html<[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>,
 #body<[#article<%{id: "main-content"}
  [#section<%{class: ["intro", "article"]} ["#"]>,
   #section<%{class: ["conclusion", "article"]} ["#"]>]>]>]>

iex> Eml.transform(e, fn x -> if Element.has?(x, class: "article"), do: Element.content(x, "#"), else: nil end)
nil
```
The last result may seem unexpected, but the `section` elements aren't
returned because `Eml.transform` first evaluates a parent node, before
continuing with its children. If the parent node gets removed,
the children will be removed too and won't get evaluated.


#### Encoding data in Eml

In order to provide conversions from various data types, Eml provides the `Eml.Data`
protocol. Eml provides a implementation for strings, numbers and atoms, but you can
provide a protocol implementation for your own types by just implementing a `to_eml`
function that converts your type to a valid Eml node. Most functions in Eml that need
type conversions don't directly call `Eml.Data.to_eml`, but use `Eml.to_content`
instead. This function adds nodes to existing content and tries to concatenate all
binary data. Furthermore, although Eml content is always a list, its
nodes can not be lists. `to_content` thus flattens all input data in order to
guarantee Eml content always is a single list.

Some examples using `Eml.to_content`
```elixir
iex> Eml.to_content(nil)
[]

iex> Eml.to_content([1, 2, h1("hello"), 4])
["12", #h1<["hello"]>, "4"]

iex> Eml.to_content(["Hello ", ["world", ["!"]]])
["Hello world!"]

iex> Eml.to_content([a: 1, b: 2])
** (Protocol.UndefinedError) protocol Eml.Data not implemented for {:b, 2}
```

### Notes

The first thing to note is that this is still a work in progress.
While it should already be pretty stable and has quite a rich API,
expect some raw edges here and there.

#### Security
Obviously, as Eml has full access to the Elixir environment,
eml should only be written by developers that already have full access
to the backend where Eml is used. Besides this, little thought has gone
into other potential security issues.

#### Validation
Eml doesn't perform any validation on the produced output.
You can add any attribute name to any element and Eml won't
complain, as it has no knowledge of the type of markup that
is to be generated. If you want to make sure that your eml code
will be valid html, render it to an html file and use this file with any
existing html validator. In this sense Eml is the same as hand
written html.

#### HTML Parser
The main purpose of the html parser is to parse back generated html
from Eml. It's a custom parser written in about 500 LOC,
so don't expect it to successfully parse every html in the wild.

Most notably, it doesn't understand attribute values without quotes and arbitrary
elements without proper closing, like `<div>`. An element should always be written
as `<div/>`, or `<div></div>`. However, explicit exceptions are made for void
elements that are expected to never have any child elements.

The bottom line is that whenever the parser fails to parse back generated
html from Eml, it is a bug and please report it. Whenever it fails to
parse some external html, I'm still interested to hear about it, but I
can't guarantee I can or will fix it.
