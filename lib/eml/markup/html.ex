defmodule Eml.Markup.Html do
  use Eml.Markup.Generator, tags: [:html, :head, :title, :base, :link, :meta, :style,
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
  defmacro __using__(_opts) do
    quote do
      import Kernel, except: [div: 2]
      import unquote(__MODULE__)
      alias unquote(__MODULE__).Presets, warn: false
    end
  end
end
