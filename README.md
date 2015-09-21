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
- [Compiling](#compiling)
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
to a call to `%Eml.Element{...}`, a struct that is the actual representation of
elements, so they can even be used inside a match.
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

iex> %Element{tag: :div, attrs: %{id: "some-id"}, content: "some content"}
#div<%{id: "some-id"} "some content">
```

Note that attributes are stored internally as a map.


#### Compiling

Contents can be compiled to a string by calling `Eml.compile`. Eml automatically
inserts a doctype declaration when the html element is the root.
```elixir
iex> html(body(div(42))) |> Eml.compile
"<!doctype html>\n<html><body><div>42</div></body>\n</html>"

iex> "text & more" |> div |> body |> html |> Eml.compile
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

The html parser is primarily written to parse html compiled by Eml, but it's
flexible enough to parse most html you throw at it. Most notable missing
features of the parser are attribute values without quotes and elements that are
not properly closed.


#### Compiling and templates

Compiling and templates can be used in situations where most content is static
and performance is critical, since its contents gets precompiled during compiletime.

Eml uses the assigns extension from `EEx` for parameterizing templates. See
the `EEx` docs for more info about them. The function that the template macro
defines accepts optionally any Dict compatible dictionary as argument for
binding values to assigns.

```elixir
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
```

Eml templates provides two ways of executing logic during runtime. By
providing assigns handlers to the optional `funs` dictionary, or by calling
external functions during runtime with the `&` operator.

```elixir
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
```

Templates are composable, so they are allowed to call other templates. The
only catch is that it's not possible to pass an assign to another template
during precompilation. The reason for this is that the logic in a template is
executed the moment the template is called, so if you would pass an assign
during precompilation, the logic in a template would receive this assign
instead of its result, which is only available during runtime. This all means
that when you for example want to pass an assign to a nested template, the
template should be prefixed with the `&` operator, or in other words, executed
during runtime.

```elixir
template templ1,
num: &(&1 + &1) do
  div @num
end

template templ2 do
 h2 @title
 templ1(num: @number) # THIS GENERATES A COMPILE TIME ERROR
 &templ1(num: @number) # THIS IS OK
end
```

Note that because the body of a template is evaluated at compile time, it's
not possible to call other functions from the same module without using `&`
operator.

Instead of defining a do block, you can also provide a path to a file with the
`:file` option.

```elixir
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
```

#### Components and fragments

Eml also provides `component/3` and `fragment/3` macros for defining
template elements. They behave as normal elements, but they
aditionally contain a template function that gets called with the
element's attributes and content as arguments during compiling.

```elixir
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
```

Just like templates, its body gets precompiled and assigns, assign
handlers and function calls prefixed with the `operator` are evaluated
at runtime. All attributes of the element can be accessed as assigns
and the element contents is accessable as the assign `@__CONTENT__`.

The main difference between templates and components is their
interface. You can use components like normal elements, even within a
match.

In addition to components, Eml also provides fragments. The difference
between components and fragments is that fragments are without any
logic, so assign handlers or the `&` capture operator are not allowed
in fragment definitions.

Fragments can be used for better composability and performance,
because unlike templates and components, assigns are allowed as
arguments during precompilation for fragments. This is possible
because fragments don't contain any logic.


#### Unpacking

In order to easily access the contents of elements, Eml provides `unpack/1`.
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

As you can see every node of the tree is passed to `Enum`. Let's continue with
some other examples.
```elixir 
iex> Enum.member?(e, "TODO") true

iex> Enum.filter(e, &Eml.match?(&1, tag: :h3))
[#h3<"Hello world">]

iex> Enum.filter(e, Eml.match?(&1, attrs: %{class: "article"}))
[#section<%{class: "article"} [#h3<"Hello world">]>,
 #section<%{class: "article"} ["TODO"]>]
```


#### Transforming eml

Eml also provides `Eml.transform/2`. `transform` mostly works like
enumeration. The key difference is that `transform` returns a modified version
of the eml tree that was passed as an argument, instead of collecting nodes in a
list.  `transform` passes any node it encounters to the provided transformation
function. This transformer can return any data or `nil`, in which case the node
is discarded, so it works a bit like a map and filter function in one pass.
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
The last result may seem unexpected, but the result is `nil` because
`Eml.transform` first evaluates a parent node, before continuing with its
children. If the parent node gets removed, the children will be removed too and
won't get evaluated.


#### Encoding data in Eml

In order to provide conversions from various data types, Eml provides the
`Eml.Encoder` protocol. It is used internally by Eml's compiler. Eml provides a
implementation for strings, numbers, tuples and atoms, but you can provide a
protocol implementation for your own types by just implementing a `encode`
function that converts your type to a valid `Eml.Compiler.node_primitive` type.

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
will be valid html, compile it to an html file and use this file with any
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
