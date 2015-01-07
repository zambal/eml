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
Eml.write! eml do
  name = "Vincent"
  age  = 36

  div class: "person" do
    div [], [ span([], "name: "), span([], name) ]
    div [], [ span([], "age: "), span([], age) ]
  end
end
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

Except for some key functions in the `Eml` module, not much reference
documentation exists currently. Please read on for a walk-through that
tries to cover most of Eml's features.


### Why?
There's currently not much in the Elixir eco system that helps with
writing markup. Elixir has Eex and there are some template language
implementations in Erlang that can be used, but I'm actually not particularly
fond of template languages. Templates itself are fine, Eml has them too,
but I'm mostly not a fan of the *language* part. In my opinion they are either
too simple, or too complex, making you almost learn a complete programming
language before they can be used effectively. Eml tries to fill this
gap by providing the developer all the power of Elixir itself when working
with markup.


### Walk-through

#### Intro

```elixir
iex(1)> use Eml
nil
```
Invoking `use Eml` translates to:
```elixir
import Eml, only: [eml: 1, defmarkup: 2, unpack: 1]
alias Eml.Markup
alias Eml.Template
```

The `eml` macro by default imports all generated html markup macros
from `Eml.Markup.Html` in to its local scope. These macro's just translate
to a call to `Eml.Markup.new`, except when used as a pattern in a match operation.
When used inside a match, the macro will be translated to the for %Eml.Markup{...}.
`eml` returns data of the type `Eml.content`, which is a list of `Eml.element`
elements. Elements can be of the type `binary`, `Eml.Markup.t`, `Eml.Parameter.t`,
or `Eml.Template.t`. We'll focus on binaries and markup for now.
```elixir
iex(2)> eml do: div([], 42)
[#div<["42"]>]
```
Here we created a `div` element with `"42"` as it contents. Since content element's
only primitive data type is binaries, the integer automatically gets converted.
Eml also provides the `defmarkup` macro. It works like defining a regular Elixir
function, but anything you write in the function definition get's evaluated as if
it were in an `eml` do block.


#### Unpacking

To access the `div` element from the returned contents, you can use `unpack`
```elixir
iex(3)> unpack eml do: div([], 42)
#div<["42"]>
```
If you want to get the contents of the div element, you can use unpack again
```elixir
iex(4)> unpack unpack eml do: div([], 42)
"42"
```
Since unpacking recursive data this way gets tiring pretty fast, Eml also provides
a recursive version called `unpackr`. Note that this function, as most others,
is not automatically imported in to local scope.
```elixir
iex(5)> Eml.unpackr eml do: div([], 42)
"42"
```


#### Writing

Contents can be written to a string by calling `Eml.write`.
Notice that Eml automatically inserts a doctype declaration when
the html element is the root.
```elixir
iex(6)> Eml.write(eml(do: html(body(div([], 42)))))
{:ok,
 "<!doctype html>\n<html><body><div>42</div></body>\n</html>"}
```
Eml also provides a version of write that either succeeds, or raises an exception.
```elixir
iex(7)> Eml.write!(eml(do: html(body(div([], 42)))))
"<!doctype html>\n<html><body><div>42</div></body></html>"
```
In practice, you rarely encounter situations that need as much brackets as in this
example. Using do blocks, as can be seen in the introductory example,
is more convenient most of the time.

#### Languages
Let's turn back to Eml's data types. Mostly you'll be using binaries and markup. In
order to provide translations from custom data types, Eml provides the `Eml.Readable`
protocol. Primitive types are handles by languages.

A language implements the Eml.Language behaviour, providing a `read`, `write` and
`markup?` function. The `read` function converts types like strings, integers and
floats in to eml. The `write` function converts eml in to whatever representation the
language has. In practice this will be mostly binary. The `markup?` function tells
if the language provides markup macros. By default Eml provides two languages:
`Eml.Language.Native` and `Eml.Language.Html`. `Eml.Language.Native` is a bit of a
special case, as it has no markup and is used internally in Eml. It is responsible
for all conversions inside an `eml` block, like the conversion from a integer we saw
in previous examples. `Eml.Language.Html` however is a language that the Eml core has
no knowledge of, other than that it is specified as the default language when defining
markup and is used by default in all read and write functions. Other languages can be
implemented as long as it implements the Eml.Language behaviour.

#### Reading

The `Eml.Language.Html` reader provides a translation from binaries in to Eml markup.
```elixir
iex(8)> Eml.read "<!doctype html>\n<html><body><div>42</div></body></html>"
[#html<[#body<[#div<["42"]>]>]>]
```
`Eml.read` also accepts `Eml.Language.Native` as a reader,
because it follows the Eml.Language behaviour too.
```elixir
iex(9)> Eml.read("<div>42</div>", Eml.Language.Native)
["<div>42</div>"]
```
No conversion of strings is performed by the native reader.
Here are a few other examples of conversion the native reader
performs.
```elixir
iex(10)> Eml.read(nil, Eml.Language.Native)
[]

iex(11)> Eml.read([1, 2, (eml do: h1([], "hello")), 4], Eml.Language.Native)
["12", #h1<["hello"]>, "4"]

iex(12)> Eml.read([a: 1, b: 2], Eml.Language.Native)
{:error, "Unreadable data: {:a, 1}"}

iex(13)> Eml.read(["Hello ", [2014, ["!"]]], Eml.Language.Native)
["Hello 2014!"]
```
`nil` is a non-existing value in Eml. As will be later shown, it can be used to discard
elements when traversing an eml tree. The other examples show the reader also tries to
concatenate all binary data. Furthermore, although Eml content is always a list, its
elements can not be lists. The native reader thus flattens all input data in order to
guarantee Eml content always is a single list. Tuples aren't supported by default,
as can be seen in the last example.


#### Querying eml

`Eml.Markup` implements the Elixir `Enumerable` protocol for traversing a tree of
elements. Let's start with creating something to query
```elixir
iex(14)> e = eml do
...(14)>   html do
...(14)>     head class: "head" do
...(14)>       meta charset: "UTF-8"
...(14)>     end
...(14)>     body do
...(14)>       article id: "main-content" do
...(14)>         section class: ["intro", "article"] do
...(14)>           h3 [], "Hello world"
...(14)>         end
...(14)>         section class: ["conclusion", "article"] do
...(14)>           "TODO"
...(14)>         end
...(14)>       end
...(14)>     end
...(14)>   end
...(14)> end
[#html<[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>,
  #body<[#article<%{id: "main-content"}
   [#section<%{class: ["intro", "article"]} [#h3<["Hello world"]>]>,
    #section<%{class: ["conclusion", "article"]} ["TODO"]>]>]>]>]
```

If we want to traverse the complete tree, we should unpack the result from `eml`,
because otherwise we would pass a list with one argument to an `Enum` function. To
get an idea how the tree is traversed, first just print all elements
```elixir
iex(15)> Enum.each(unpack(e), fn x -> IO.puts(inspect x) end)
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

As you can see every element of the tree is passed to `Enum`.
Let's continue with some other examples
```elixir
iex(16)> Enum.member?(unpack(e), "TODO")
true

# `Eml.Markup` is automatically aliased as `Markup` when `use Eml` is invoked.
iex(17)> Enum.filter(unpack(e), &Markup.has?(&1, tag: :h3))
[#h3<["Hello world"]>]

iex(18)> Enum.filter(unpack(e), &Markup.has?(&1, class: "article"))
[#section<%{class: ["intro", "article"]} [#h3<["Hello world"]>]>,
 #section<%{class: ["conclusion", "article"]} ["TODO"]>]

iex(19)> Enum.filter(unpack(e), &Markup.has?(&1, tag: :h3, class: "article"))
[]
```

Eml also provides the `Eml.select` and `Eml.member?` functions, which
can be used to select content and check for membership more easily.
Note that you don't need to unpack, as `Eml.select` and all Eml transformation
functions work recursively with lists. Check the docs for more info about
the options `Eml.select` accepts.
```elixir
iex(20)> Eml.select(e, class: "article")
[#section<%{class: ["intro", "article"]} [#h3<["Hello world"]>]>,
 #section<%{class: ["conclusion", "article"]} ["TODO"]>]

# using `parent: true` instructs `Eml.select` to select the parent
# of the matched element(s)
iex(21)> Eml.select(e, tag: :meta, parent: true)
[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>]

# when using the :pat option, a regular expression can be used to
# match binary content
iex(22)> Eml.select(e, pat: ~r/H.*d/)
["Hello world"]

iex(23)> Eml.select(e, pat: ~r/TOD/, parent: true)
[#section<%{class: ["conclusion", "article"]} ["TODO"]>]

iex(24)> Eml.member?(e, class: "head")
true

iex(25)> Eml.member?(e, tag: :article, class: "conclusion")
false
```


#### Transforming eml

Eml provides three high-level constructs for transforming eml: `Eml.update`,
`Eml.remove`, and `Eml.add`. The last doesn't have the `:pat` option, but
has an `:at` option instead. Like `Eml.select` they traverse the complete
eml tree. Check the docs for more info about these functions. The following
examples work with the same eml snippet as in the previous section.

```elixir
iex(26)> Eml.remove(e, class: "article")
[#html<[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>,
  #body<[#article<%{id: "main-content"}>]>]>]

iex(27)> Eml.remove(e, pat: ~r/orld/)
[#html<[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>,
  #body<[#article<%{id: "main-content"}
   [#section<%{class: ["intro", "article"]} [#h3<>]>,
    #section<%{class: ["conclusion", "article"]} ["TODO"]>]>]>]>]

iex(28)> Eml.update(e, &String.downcase(&1), pat: ~r/.*/)
[#html<[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>,
  #body<[#article<%{id: "main-content"}
   [#section<%{class: ["intro", "article"]} [#h3<["hello world"]>]>,
    #section<%{class: ["conclusion", "article"]} ["todo"]>]>]>]>]

iex(29)> Eml.add(e, eml(do: section([class: "pre-intro"}, "....")), id: "main-content", at: :begin)
[#html<[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>,
  #body<[#article<%{id: "main-content"}
   [#section<%{class: "pre-intro"} ["...."]>,
    #section<%{class: ["intro", "article"]} [#h3<["Hello world"]>]>,
    #section<%{class: ["conclusion", "article"]} ["TODO"]>]>]>]>]

iex(30)> Eml.add(e, eml(do: section([class: "post-conclusion"}, "....")), id: "main-content", at: :end)
[#html<[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>,
  #body<[#article<%{id: "main-content"}
   [#section<%{class: ["intro", "article"]} [#h3<["Hello world"]>]>,
    #section<%{class: ["conclusion", "article"]} ["TODO"]>,
    #section<%{class: "post-conclusion"} ["...."]>]>]>]>]
```

Eml also provides `Eml.transform`. All functions from the previous section are
implemented with it. `Eml.transform` mostly works like enumeration. The key
difference is that `Eml.transform` returns a modified version of the eml tree that
was passed as an argument, instead of collecting elements in a single list.
`Eml.transform` passes any element it encounters to the provided transformation
function. The transformation function can return any readable data or `nil`,
in which case the element is discarded, so it works a bit like a map and filter
function in one pass.
```elixir
iex(31)> Eml.transform(e, fn x -> if Markup.has?(x, class: "article"), do: Markup.content(x, "#"), else: x end)
[#html<[#head<%{class: "head"} [#meta<%{charset: "UTF-8"}>]>,
  #body<[#article<%{id: "main-content"}
   [#section<%{class: ["intro", "article"]} ["#"]>,
    #section<%{class: ["conclusion", "article"]} ["#"]>]>]>]>]

iex(32)> Eml.transform(e, fn x -> if Markup.has?(x, class: "article"), do: Markup.content(x, "#"), else: nil end)
[]
```
The last result may seem unexpected, but the `section` elements aren't
returned because `Eml.transform` first evaluates a parent element, before
continuing with its children. If the parent element gets removed,
the children will be removed too and won't get evaluated.


#### Parameters and templates

Parameters and templates can be used in situations where most content
is static and performance is critical. Templates in Eml are quite
simple and don't provide any language constructs like template languages.
This is for good reason. If anything more complex is needed than a
'fill in the blanks' template, you should use regular eml.

Let's start with a simple example
```elixir
iex(33)> e = eml do: [:atoms, " ", :are, " ", :converted, " ", :to_parameters]
[#param:atoms, " ", #param:are, " ", #param:converted, " ",
 #param:to_parameters]

iex(34)> Eml.write!(e)
"#param{atoms} #param{are} #param{converted} #param{to_parameters}"

iex(35)> Eml.write!(e, bindings: [atoms: "Atoms", are: "are", converted: "converted", to_parameters: "to parameters."])
"Atoms are converted to parameters."

iex(36)> unbound = Eml.compile(e)
#Template<[atoms: 1, are: 1, converted: 1, to_parameters: 1]>

# `Eml.Template` is automatically aliased as `Template` when `use Eml` is invoked.
iex(37)> t = Template.bind(unbound, atoms: "Atoms", are: "are")
#Template<[converted: 1, to_parameters: 1]>

iex(38)> bound = Template.bind(t, converted: "converted", to_parameters: "to parameters.")
#Template<BOUND>

iex(39)> Eml.write!(bound)
"Atoms are converted to parameters."
```
When creating eml, atoms are automatically converted to parameters.
Whenever you try to write eml that contains parameters, the parameters
are converted in to a string representation. If you have a parameter with
id `:myparam`, the string representation will be `#param{myparam}`. If Eml
reads back html that contains these strings, it will automatically convert
those in to parameters. To bind data to parameters in eml, you can either
compile eml data to a template and use its various binding options, or you
can directly bind data to parameters by calling `Eml.write` with the
`:bindings` option. If there are still unbound parameters left, `Eml.write`
will also return a template. The output of templates on Elixir's shell
provides some information about their state. The returned template at
`iex(36)` tells that it has four parameters. The returned template at
`iex(38)` tells that whatever parameters it has, they are all bound and the
template is ready to render. Parameters with the same name can occur
multiple times in a template. You can either call `Eml.Template.bind` as
many times as needed in order to bind all instances, or you can provide a
list of values who's length is at least as long as the number of
occurrences of the parameter in the template.
```elixir
iex(40)> e = eml do: [div(:fruit), div(:fruit)]
[#div<[#param:fruit]>, #div<[#param:fruit]>]

iex(41)> unbound = Eml.compile(e)
#Template<[fruit: 2]>

iex(42)> t = Template.bind(unbound, fruit: "orange")
#Template<[fruit: 1]>

iex(43)> Eml.write!(t, bindings: [fruit: "lemon"])
"<div>orange</div><div>lemon</div>"

iex(44)> t = Template.bind(unbound, fruit: ["blackberry", "strawberry"])
#Template<BOUND>

iex(45)> Eml.write!(t)
"<div>blackberry</div><div>strawberry</div>"
```


### Notes

The first thing to note is that this is still a work in progress.
While it should already be pretty stable and has quite a rich API,
expect some raw edges here and there.

#### Escaping
Hardly any work has gone into proper escaping of characters.
Eml currently assumes utf8 content for strings and only escapes `<`,
 `>` and `&` characters.

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
will be valid html, write it to an html file and use this file with any
existing html validator. In this sense Eml is the same as hand
written html.

#### Html Parser
The main purpose of the html parser is to read back generated html
from Eml. It's a custom parser written in about 500 LOC,
so don't expect it to successfully parse every html in the wild.

Most notably, it doesn't understand arbitrary elements without proper
closing, like `<div>`. An element should always be written as `<div/>`,
or `<div></div>`. However, explicit exceptions are made for void elements
that are expected to never have any child elements.

The bottom line is that whenever the parser fails to read back generated
html from Eml, it is a bug and please report it. Whenever it fails to
parse some external html, I'm still interested to hear about it, but I
can't guarantee I can or will fix it.
