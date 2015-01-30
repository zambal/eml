[![Build Status](https://api.travis-ci.org/zambal/eml.svg?branch=master)](https://travis-ci.org/zambal/eml)

# Eml

## Markup for developers

### What is it?
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
the first class citizen of a programming language, allowing you to organize view
logic with all the power of Elixir.

Please read on for a walkthrough that tries to cover most of Eml's features.


### Walkthrough

- [Intro](#intro)
- [Rendering](#rendering)
- [Parsing](#parsing)
- [Parameters and templates](#parameters-and-templates)
- [Precompiling](#precompiling)
- [Unpacking](#unpacking)
- [Querying eml](#querying-eml)
- [Transforming eml](#transforming-eml)
- [Languages and parser behaviour](#languages-and-parser-behaviour)


#### Intro

```elixir
iex> use Eml.Language.HTML
nil
```

By invoking `use Eml.Language.HTML` all generated html element macros from
`Eml.Language.HTML.Elements` are imported in to the current scope. Note that
`use Eml.Language.HTML` also unimports Kernel.div/2, as it would otherwise clash
with the div element macro, so if you want to use `Kernel.div/2` in the same scope,
you'll have to call it with the module name. The element macro's just translate to a
call to `Eml.Element.new`, except when used as a pattern in a match operation.
When used inside a match, the macro will be translated to %Eml.Element{...}. The nodes
of an element can be `String.t`, `Eml.Element.t`, `Eml.Parameter.t`, or `Eml.Template.t`.
We'll focus on strings and elements for now.
```elixir
iex> div 42
#div<["42"]>
```
Here we created a `div` element with `"42"` as it contents.Since Eml content's
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

Note that attributes are stored internally as a map.


#### Rendering

Contents can be rendered to a string by calling `Eml.render`.
Eml automatically inserts a doctype declaration when the html
element is the root.
```elixir
iex> html(body(div(42))) |> Eml.render
"<!doctype html>\n<html><body><div>42</div></body>\n</html>"

iex> "text & more" |> div |> body |> html |> Eml.render
"<!doctype html>\n<html><body><div>text &amp; more</div></body></html>"
```
As you can see, you can also use Elixir's pipe operator for creating markup.
However, using do blocks, as can be seen in the introductory example,
is more convenient most of the time. By default, Eml also converts `&`,
`<` and `>` characters in content or attribute values to entities, but this
behaviour can also be switched off.


#### Parsing

Eml's parser by default converts a string with html content in to Eml content.
```elixir
iex> Eml.parse "<!doctype html>\n<html><head><meta charset='UTF-8'></head><body><div>42</div></body></html>"
[#html<[#head<[#meta<%{charset: "UTF-8"}>]>, #body<[#div<["42"]>]>]>]

iex> Eml.parse "<div class=\"content article\"><h1 class='title'>Title<h1><p class=\"paragraph\">blah &amp; blah</p></div>"
#div<%{class: ["content", "article"]}
 [#h1<%{class: "title"}
  ["Title", #h1<[#p<%{class: "paragraph"} ["blah & blah"]>]>]>]>
```

The html parser is primarily written to parse html rendered by Eml, but it's
flexible enough to parse most html you throw at it. Most notable missing features
of the parser are attribute values without quotes and elements that are not properly
closed.


#### Parameters and templates

Parameters and templates can be used in situations where most content
is static and performance is critical. Templates in Eml are quite
simple and don't provide any language constructs like template languages.
This is for good reason. If anything more complex is needed than a
'fill in the blanks' template, you should use regular `eml`.

Let's start with a simple example
```elixir
iex> e = h1 [:atoms, " ", :are, " ", :converted, " ", :to_parameters]
#h1<[#param:atoms, " ", #param:are, " ", #param:converted, " ",
 #param:to_parameters]>

iex> Eml.render(e, atoms: "Atoms", are: "are", converted: "converted", to_parameters: "to parameters.")
"<h1>Atoms are converted to parameters.</h1>"

iex> Eml.render(e, [], render_params: true)
"<h1>#param{atoms} #param{are} #param{converted} #param{to_parameters}</h1>"

iex> unbound = Eml.compile(e)
#Template<[:atoms, :are, :converted, :to_parameters]>

iex> t = Eml.Template.bind(unbound, atoms: "Atoms", are: "are")
#Template<[:converted, :to_parameters]>

iex> bound = Eml.Template.bind(t, converted: "converted", to_parameters: "to parameters.")
#Template<BOUND>

iex> Eml.render(bound)
"<h1>Atoms are converted to parameters.</h1>"
```
When creating eml, atoms are automatically converted to parameters.
Whenever you render eml with the `render_params: true` option, parameters
are converted in to a string representation. If Eml parses back html that
contains these strings, it will automatically convert those in to parameters.
To bind data to parameters in eml, you can either compile eml data to a template
and use its various binding options, or you can directly bind data to parameters
by providing bindings to `Eml.render`. If there are still unbound parameters left,
`Eml.render` will return a error. The output of templates on Elixir's shell provide
s some information about their state. The returned template in the 4th example
tells that it has four unbound parameters. The returned template in the second last
example tells that whatever parameters it has, they are all bound and the template
is ready to render. Parameters with the same name can occur multiple times in a
template.

#### Precompiling

Eml also provides a precompile macro. `eml` code inside a precompile block will be
compiled to a template during compile time of your project. In other words, the code
gets evaluated when for example you invoke `mix compile`. the precompile macro can be
called in two ways: inside a function and inside a module. When called inside a
function it will return the compiled template and when called inside a module it will
define a function that returns the template when called. Lets start with an example
that uses precompile in a function (or in this case, in the interpreter)
```elixir
# Calling `use Eml` imports its macro's
iex> use Eml
iex> t = precompile do
...>   div do
...>     span :a
...>     span :b
...>   end
...> end
#Template<[:a, :b]>
iex> Eml.render t, a: 1, b: 2
"<div><span>1</span><span>2</span></div>"
```

Of course, calling `precompile` from iex doesn't make much sense, because the
precompiling is done on the fly and doesn't give any performance benefits
compared to `Eml.compile`.

An example using precompile in a module
```elixir
iex> defmodule PrecompileTest do
...>   use Eml
...>   precompile my_template do
...>     div do
...>       span :a
...>       span :b
...>     end
...>   end
...> end
{:module, PrecompileTest,
 <<...>>,
 {:my_template, 1}}
iex> PrecompileTest.my_template(a: 42, b: 43) |> Eml.render
"<div><span>42</span><span>43</span></div>"
```

As you can see, using precompile in a module defines a function that (optionally) accepts a
list of bindings.

Instead of defining a block of `eml`, `precompile` also accepts a path to a file. See the
documentation for more info about the options of `precompile`

**WARNING**

Since the code in a precompile block is evaluated during compile time, you can't call
functions or macro's from the same module, since the module isn't compiled yet. Also
you can't reliably call functions or macro's from other modules in the same project as
they might still not be compiled. Calling functions or macro's from dependencies should
work, as Elixir always compiles dependencies before the project itself.

Generally, you want to keep your templates as pure as possible.


#### Unpacking

Since the contents of elements are always wrapped in a list, Eml provides
a utility function to easily access the contents.
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

# `Eml.Element` is automatically aliased as `Element` when `use Eml` is invoked.
iex> Enum.filter(e, &Eml.Element.has?(&1, tag: :h3))
[#h3<["Hello world"]>]

iex> Enum.filter(e, &Eml.Element.has?(&1, class: "article"))
[#section<%{class: ["intro", "article"]} [#h3<["Hello world"]>]>,
 #section<%{class: ["conclusion", "article"]} ["TODO"]>]

iex> Enum.filter(e, &Eml.Element.has?(&1, tag: :h3, class: "article"))
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
was passed as an argument, instead of collecting nodes in a single list.
`Eml.transform` passes any node it encounters to the provided transformation
function. The transformation function can return any parsable data or `nil`,
in which case the node is discarded, so it works a bit like a map and filter
function in one pass.
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


#### Languages and parser behaviour

Let's turn back to Eml's data types. A language implements the Eml.Language behaviour,
providing a `parse`, `render` and `element?` function. The `parse` function converts strings
in to eml. The `render` function converts eml in to whatever string representation the
language has. The `element?` function tells if the language provides element macros.
By default Eml provides `Eml.Language.HTML`. Other languages can be implemented as long as
it implements the Eml.Language behaviour.

In order to provide translations from various data types, Eml provides the `Eml.Data`
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
