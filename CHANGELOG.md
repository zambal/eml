# Changelog

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
