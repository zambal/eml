defmodule Eml.HTML do
  @moduledoc """
  This is the container module of all the generated HTML element macro's.

  To import all these macro's into current scope, invoke `use Eml.HTML`
  instead of `import Eml.HTML`, because it also handles ambiguous named elements.
  """

  use Eml.Element.Generator,
  generate_catch_all: true,
  tags: [:html, :head, :title, :base, :link, :meta, :style,
         :script, :noscript, :body, :div, :span, :article,
         :section, :nav, :aside, :h1, :h2, :h3, :h4, :h5, :h6,
         :header, :footer, :address, :p, :hr, :pre, :blockquote,
         :ol, :ul, :li, :dl, :dt, :dd, :figure, :figcaption, :main,
         :a, :em, :strong, :small, :s, :cite, :q, :dfn, :abbr, :data,
         :time, :code, :var, :samp, :kbd, :sub, :sup, :i, :b, :u, :mark,
         :ruby, :rt, :rp, :bdi, :bdo, :br, :wbr, :ins, :del, :img, :iframe,
         :embed, :object, :param, :video, :audio, :source, :track, :canvas, :map,
         :area, :svg, :math, :table, :caption, :colgroup, :col, :tbody, :thead, :tfoot,
         :tr, :td, :th, :form, :fieldset, :legend, :label, :input, :button, :select,
         :datalist, :optgroup, :option, :textarea, :keygen, :output, :progress,
         :meter, :details, :summary, :menuitem, :menu]

end
