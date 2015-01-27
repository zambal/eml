# Changelog

## v0.6.0-dev

 * Enhancements
   * Introduced `use Eml.Language.Html` as prefered way of defininf markup
   * Restructured README.md and added new content about precompiling
   * It's now possible to pass content as the first argument of an element macro, ie. `div "Hello world!"` 

 * Bug fixes
  * Documentation corrections.
  * Removed duplicate code in `Eml.defhtml/2`
  * Type specification fixes
  * `Eml.parse/2` in some cases returned weird results when the input is a list

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
