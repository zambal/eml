# Changelog

## v0.9.0-dev
 * Enhancements
  * Replaced quoted expressions with assign handlers and runtime function calls
  * `use Eml` can now be used to set compile options and elements to import

 * Bug fixed
  * Fixed typo in Eml.Element.apply_template/1

 * Backwards incompatible changes
  * Quoted expressions are now invalid. Use assign handlers or runtime function calls instead.

## v0.8.0-dev
 * Enhancements
  * Much richer templates by using quoted expressions as replacement for parameters
  * Removed all generic functionality from the html parser and renderer,
    which makes it easier to implement other parsers and renderers
  * Added `{ :safe, String.t }` as a new content type which you can use when you need to add content to an element that should not get escaped
  * Added `transform` option to `Eml.render/3`
  * Added `casing` option to `Eml.Element.Generator.__using__` to control the casing of tags for generated elements
  * Added the `&` capture operator as shortcut for quoted expressions
  * Introduced components and fragments
  * Added `Eml.match?/2` macro
  * Added `Eml.Element.put_template/3`, `Eml.Element.remove_template/1` and `Eml.apply_template/1` functions
  * Added `any` element as a catch all tag macro to be used in a match
  * Added `Eml.escape/1` and `Eml.unescape/1` functions that recursively escape or unescape content.
  * `Eml.Compiler.compile` returns results by default as `{ :safe, result }` so that
    they can be easily added to other elements, witout getting escaped

 * Bug fixes
  * Using element macro's in a match had different confusing behaviour

 * Backwards incompatible changes
  * Removed `Eml.Template` and `Eml.Parameter` in favor of quoted expressions
  * Replaced `Eml.precompile` with `Eml.template` and `Eml.template_fn`
  * Changed names of render options: :lang => :renderer, :quote => :quotes
  * Importing all HTML element macro's is now done via `use Eml.HTML` instead of `use Eml.Language.HTML`
  * Renamed `Eml.Data` protocol to `Eml.Encoder` and removed `Eml.to_content`
  * Data conversion is now only done during compiling and not when adding data to elements.
  * Removed query functions
  * Removed transform functions
  * Removed `defeml` and `defhtml` macros
  * Removed `Eml.unpackr/1` and `Eml.funpackr/1`. `Eml.unpack` now always unpacks recursively
  * Removed `Eml.element?/1`, `Eml.empty?/1` and `Eml.type/1` functions.
  * Removed all previous helper functions from `Eml.Element`
  * Removed `Eml.compile/2` in favor of `Eml.Compiler.compile/2`
  * Parser doesn't automatically converts entities anymore. Use `Eml.unescape/1` instead.

## v0.7.1
 * Enhancements
  * Added unit tests that test escaping and enity parsing
  * Documentation additions and corrections

 * Bug fixes
  * Single and double quotes in attributes now should get properly escaped

 * Backwards incompatible changes

## v0.7.0
 * Enhancements
  * It's now easy to provide conversions for custom data types by using the new `Eml.Data` protocol
  * Better separation of concerns by removing all data conversions from parsing

 * Bug fixes
  * Some type fixes in the Eml.Language behaviour

 * Backwards incompatible changes
  * Renamed `Eml.Language.Html` to `Eml.Language.HTML` in order to be compliant with Elixir's naming conventions
  * The undocumented `Eml.parse/4` function is now replaced by `Eml.to_content/3`
  * The `Eml.Parsable` protocol is replaced by `Eml.Data`, which is now strictly used for converting various
    data types into valid Eml nodes.
  * `Eml.parse/2` now always returns a list again, because the type
    conversions are now done by `Eml.to_content/3` and consequently you can't force
    `Eml.parse/2` to return a list anymore, which would make it dangerous to
    use when parsing html partials where you don't know the nummer of nodes.
  * `Eml.parse/2`, `Eml.render/3` and `Eml.compile/3` now always raise an exception on error.
     Removed `Eml.parse!/2`, `Eml.render!/3` and `Eml.compile!/3`. Reason is that it was hard
     to guarantee that those functions never raised an error and it simplifies Eml's API
  * Removed `Eml.render_to_eex/3`, `Eml.render_to_eex!/3`, `Eml.compile_to_eex/3` and `Eml.compile_to_eex!/3`,
    as they didn't provide much usefulness

## v0.6.0

 * Enhancements
   * Introduced `use Eml.Language.Html` as prefered way of defining markup
   * Restructured README.md and added new content about precompiling
   * It's now possible to pass content as the first argument of an element macro, ie. `div "Hello world!"`
   * Added `Eml.compile_to_eex/3` and `Eml.render_to_eex/3`

 * Bug fixes
  * Documentation corrections.
  * Removed duplicate code in `Eml.defhtml/2`
  * Type specification fixes
  * `Eml.parse/2` in some cases returned weird results when the input is a list
  * Template bindings were not correctly parsed

 * Backwards incompatible changes
  * Removed `Eml.eml/2` in favor of `use Eml.Language.Html`
  * `Eml.parse/2` now returns results in the form of `{ :ok, res }`, in order to be consistent with render and compile functions
  * Unless the input of `Eml.parse/2` is a list, if the result is a single element, `Eml.parse/2` now just returns the single element
    instead of always wrapping the result in a list


## v0.5.0

 * Enhancements
  * Added documentation for all public modules
  * Added some meta data to mix.exs for ex_doc
  * Added `Eml.compile!/3`

 * Bug fixes
  * Lots of documentation corrections
  * Some type fixes

 * Backwards incompatible changes
  * Renamed all read function to parse
  * Renamed all write functions to render
  * Removed `Eml.write_file` and `Eml.write_file!`
  * Removed `Eml.read_file` and `Eml.read_file!`
  * Parameters with the same name just reuse the same bounded value, instead of popping a list of bounded values
  * Renamed the module `Eml.Markup` to `Eml.Element` and the module `Eml.Language.Html.Markup` to `Eml.Language.Html.Elements`
  * `Eml.compile` now returns { :ok, template } on success instead of just the template in order to be consistent with Eml's
    render and parse functions
