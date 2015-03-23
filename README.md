[![Build Status](https://api.travis-ci.org/zambal/eml.svg?branch=master)](https://travis-ci.org/zambal/eml)

# Eml

## Markup for developers

### What is it?
Eml makes markup a first class citizen in Elixir. It provides a flexible and
modular toolkit for generating, parsing and manipulating markup. It's main focus
is html, but other markup languages could be implemented as well.

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

### Why?
Most templating libraries are build around the idea of interpreting strings that
can contain embeded code. This code is mostly used for implementing view logic
in the template. You could say that these libraries are making code a first
class citizen in template strings. As long as the view logic is simple this
works pretty well, but with more complex views this can become quite messy. Eml
takes this idea inside out and makes the markup that you normally would write as
a string a first class citizen of the programming language, allowing you to
compose and organize markup and view logic with all the power of Elixir.

Please read on for a walkthrough that tries to cover most of Eml's features.


### Walkthrough

- [Intro](#intro)
- [Rendering](#rendering)
- [Parsing](#parsing)
- [Compiling and templates](#compiling-and-templates)
- [Components and fragments](#components-and-fragments)
- [Unpacking](#unpacking)
- [Querying eml](#querying-eml)
- [Transforming eml](#transforming-eml)
- [Encoding data in Eml](#encoding-data-in-eml)
- [Notes](#notes)

#### Intro

```elixir
iex> use Eml
nil
iex> use Eml.HTML
nil
```

By invoking `use Eml`, some macro's are imported into the current scope and core
API modules are aliased. `use Eml.HTML` imports all generated html element
macros from `Eml.HTML` into the current scope. The element macros just translate
to a call to `%Eml.Element{...}`, so they can even be used inside a match.
```elixir
iex> div 42
#div<42>
```
Here we created a `div` element with `42` as it contents.

The element macro's in Eml try to be clever about the type of arguments that get
passed. For example, if the first argument is a Keyword list, it will be
interpreted as attributes, otherwise as content.
```elixir
iex> div id: "some-id"
#div<%{id: "some-id"}>

iex> div "some content"
#div<"some content">

iex> div do
...>   "some content"
...> end
#div<["some content"]>

iex> div [id: "some-id"], "some content"
#div<%{id: "some-id"} "some content">

iex> div id: "some-id" do
...>   "some content"
...> end
#div<%{id: "some-id"} ["some content"]>
```

Note that attributes are stored internally as a map.


#### Rendering

Contents can be rendered to a string by calling `Eml.render`. Eml automatically
inserts a doctype declaration when the html element is the root.
```elixir
iex> html(body(div(42))) |> Eml.render
"<!doctype html>\n<html><body><div>42</div></body>\n</html>"

iex> "text & more" |> div |> body |> html |> Eml.render
"<!doctype html>\n<html><body><div>text &amp; more</div></body></html>"
```
As you can see, you can also use Elixir's pipe operator for creating markup.
However, using do blocks, as can be seen in the introductory example, is more
convenient most of the time.

#### Parsing

Eml's parser by default converts a string with html content into Eml content.
```elixir
iex> Eml.parse "<!doctype html>\n<html><head><meta charset='UTF-8'></head><body><div>42</div></body></html>"
[#html<[#head<[#meta<%{charset: "UTF-8"}>]>, #body<[#div<"42">]>]>]

iex> Eml.parse "<div class=\"content article\"><h1 class='title'>Title<h1><p class=\"paragraph\">blah &amp; blah</p></div>"
[#div<%{class: "content article"}
 [#h1<%{class: "title"}
  ["Title", #h1<[#p<%{class: "paragraph"} "blah & blah">]>]>]>]
```

The html parser is primarily written to parse html rendered by Eml, but it's
flexible enough to parse most html you throw at it. Most notable missing
features of the parser are attribute values without quotes and elements that are
not properly closed.


#### Compiling and templates

Compiling and templates can be used in situations where most content is static
and performance is critical. A template is just Eml content that contains quoted
expressions. `Eml.Compiler.compile/2` renders all non quoted expressions and all
quoted expressions are preprocessed for efficient rendering with `Eml.render/3
afterwards. It's not needed to work with `Eml.Compiler.compile/2` directly, as
using `Eml.template` and `Eml.template_fn` is more convenient in most
cases. `Eml.template` defines a function that has all non quoted expressions
prerendered and when called, concatenates the results from the quoted
expressions with it. `Eml.template_fn` works the same, but returns an anonymous
function instead.

Eml uses the assigns extension from `EEx` for easy data access in a
template. See the `EEx` docs for more info about them. Since all runtime
behaviour is written in quoted expressions, assigns need to be quoted too. To
prevent you from writing things like `quote do: @my_assign + 4` all the time,
Eml provides the `&` capture operator as a shortcut for `quote do: ...`. You can
use this shortcut only in template and component macro's. This means that for
example `div &(@a + 4)` and `div (quote do: @a + 4)` have the same result inside
a template. If you just want to pass an assign, you can even leave out the
capture operator and just write `div @a`. The function that the template macro
defines accepts optionally a Keyword list for binding values to assigns.
```elixir
iex> e = h1 [(quote do: @assigns), " ", (quote do: @are), " ", (quote do: @pretty), " ", (quote do: @nifty)]
#h1<[{:quoted, [{:@, [line: 12], [{:assigns, [line: 12], nil}]}]}, " ",
 {:quoted, [{:@, [line: 12], [{:are, [line: 12], nil}]}]}, " ",
 {:quoted, [{:@, [line: 12], [{:pretty, [line: 12], nil}]}]}, " ",
 {:quoted, [{:@, [line: 12], [{:nifty, [line: 12], nil}]}]}]>
iex> t = Eml.compile(e)
iex> Eml.render(t, assigns: "Assigns", are: "are", pretty: "pretty", nifty: "nifty!")
"<h1>Assigns are pretty nifty!</h1>"

iex> e = ul(quote do
...>   for n <- @names, do: li n
...> end)
```
You can also call `Eml.render` directly, as it compiles content before rendering.
```elixir
iex> Eml.render e, names: ~w(john james jesse)
"<ul><li>john</li><li>james</li><li>jesse</li></ul>"

iex> t = template_fn do
...>   ul(quote do
...>     for n <- @names, do: li n
...>   end)
...> end
#Function<6.90072148/1 in :erl_eval.expr/5>
iex> t.(names: ~w(john james jesse))
"<ul><li>john</li><li>james</li><li>jesse</li></ul>"
```
To bind data to assigns in Eml, you can either compile eml data to a template
and use `Eml.render` to bind data to assigns, or you can directly call
`Eml.render`, which also precompiles on the fly when needed. However, any
performance benefits of using templates is lost this way.

Since unquoted expressions in a template are evaluated during compile time, you
can't call functions or macro's from the same module, since the module isn't
compiled yet.

Quoted expressions however have normal access to other functions, because they
are evaluated at runtime.

Templates are composable, so they are allowed to call other templates. The only
catch is that it's not possible to pass a quoted expression to a template. The
reason for this is that the logic in a template is executed the moment the
template is called, so if you would pass a quoted expression, the logic in a
template would receive this quoted expression instead of its result. This all
means that when you for example want to pass an assign to a nested template, the
template should be part of a quoted expression, or in other word, executed
during runtime.

```elixir
template templ1 do
  div &(@num + @num)
end

template templ2 do
 h2 @title
 templ1(num: @number) # THIS GENERATES A COMPILE TIME ERROR
 &templ1(num: @number) # THIS IS OK
```

See the documentation
of `Eml.template/3` for more info and examples about templates.

#### Components and fragments

Eml also provides `component/3` and `fragment/3` macros for defining template elements. They are
implemented as normal elements, but they aditionally contain a template
function that gets called with the element's attributes and content as arguments
during rendering.

```elixir
iex> use Eml
nil
iex> use Eml.HTML.Element
nil
iex> defmodule ElTest do
...>
...>   component my_list do
...>     ul class: @class do
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
```

Just like templates, all non quoted expressions get precompiled and quoted
expressions are evaluated at runtime. All attributes of the element can be
accessed as assigns and the element contents is accessable as the assign
`@__CONTENT__`.

The main difference between templates and components is their
interface. You can use components like normal elements, even within a
match.

In addition to components, Eml also provides fragments. The difference between
components and fragments is that fragments are without any logic, so quoted
expressions or the `&` capture operator are not allowed in a fragment
definition. This means that assigns don't need to be quoted.

Fragments can be used for better composability and performance, because
unlike templates and components, quoted expressions are allowed as arguments for
fragments. This is possible because fragments don't contain any logic.


#### Unpacking

Since the contents of elements are always wrapped in a list, Eml provides a
utility function to easily access its contents.
```elixir
iex> Eml.unpack div 42
42

iex> Eml.unpack div span(42)
42
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
...>       section class: "article" do
...>         h3 "Hello world"
...>       end
...>       section class: "article" do
...>         "TODO"
...>       end
...>     end
...>   end
...> end
#html<[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>,
 #body<[#article<%{id: "main-content"}
  [#section<%{class: "article"} [#h3<"Hello world">]>,
   #section<%{class: "article"} ["TODO"]>]>]>]>
```
To get an idea how the tree is traversed, first just print all nodes
```elixir
iex> Enum.each(e, fn x -> IO.puts(inspect x) end)
#html<[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>, #body<[#article<%{id: "main-content"} [#section<%{class: "article"} [#h3<"Hello world">]>, #section<%{class: "article"} ["TODO"]>]>]>]>
#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>
#meta<%{charset: "UTF-8"}>
#body<[#article<%{id: "main-content"} [#section<%{class: "article"} [#h3<"Hello world">]>, #section<%{class: "article"} ["TODO"]>]>]>
#article<%{id: "main-content"} [#section<%{class: "article"} [#h3<"Hello world">]>, #section<%{class: "article"} ["TODO"]>]>
#section<%{class: "article"} [#h3<"Hello world">]>
#h3<"Hello world">
"Hello world"
#section<%{class: "article"} ["TODO"]>
"TODO"
:ok
```

As you can see every node of the tree is passed to `Enum`.
Let's continue with some other examples
```elixir
iex> Enum.member?(e, "TODO")
true

iex> Enum.filter(e, fn
...>   h3(_) -> true
...>   _     -> false
...> end)
[#h3<"Hello world">]

iex> Enum.filter(e, fn
       any(%{class: "article"}) -> true
       _ -> false
     end)
[#section<%{class: "article"} [#h3<"Hello world">]>,
 #section<%{class: "article"} ["TODO"]>]
```


#### Transforming eml

Eml also provides `Eml.transform/2`. `transform` mostly works like
enumeration. The key difference is that `transform` returns a modified version
of the eml tree that was passed as an argument, instead of collecting nodes in a
list.  `transform` passes any node it encounters to the provided transformation
function. The transformation function can return any data or `nil`, in which
case the node is discarded, so it works a bit like a map and filter function in
one pass.
```elixir
iex> Eml.transform(e, fn
...>   any(%{class: "article"}) = el -> %{el|content: "#"}
...>   node -> node
...> end)
#html<[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>,
 #body<[#article<%{id: "main-content"}
  [#section<%{class: "article"} "#">, #section<%{class: "article"}
   "#">]>]>]>

iex> Eml.transform(e, fn
...>   any(%{class: "article"}) = el -> %{el|content: "#"}
...>   _ -> nil
...> end)
nil
```
The last result may seem unexpected, but the `section` elements aren't
returned because `Eml.transform` first evaluates a parent node, before
continuing with its children. If the parent node gets removed,
the children will be removed too and won't get evaluated.


#### Encoding data in Eml

In order to provide conversions from various data types, Eml provides the
`Eml.Encoder` protocol. It is used internally by Eml's compiler. Eml provides a
implementation for strings, numbers, tuples and atoms, but you can provide a
protocol implementation for your own types by just implementing a `encode`
function that converts your type to a valid `Eml.Compiler.chunk` type.

Some examples using `Eml.encode`
```elixir

iex> Eml.Encoder.encode 1
"1"

iex> Eml.Encoder.encode %{div: 42, span: 12}
** (Protocol.UndefinedError) protocol Eml.Encoder not implemented for %{div: 42, span: 12}

iex> defimpl Eml.Encoder, for: Map
...>   use Eml.HTML
...>   def encode(data) do
...>     for { k, v } <- data do
...>       %Eml.Element{tag: k, content: v}
...>     end
...>   end
...> end
iex> Eml.Encoder.encode %{div: 42, span: 12}
[#div<42>, #span<12>]
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
