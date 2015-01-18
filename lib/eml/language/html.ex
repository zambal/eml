defmodule Eml.Language.Html.Markup do
  @moduledoc """
  This is the container module of all the generated HTML element macro's.
  All macro's in this module are imported inside an `eml` block.
  """

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
end

defmodule Eml.Language.Html do
  @moduledoc false

  @behaviour Eml.Language

  def markup?(), do: true

  def parse(data, type) do
    Eml.Language.Html.Parser.parse(data, type)
  end

  def render(eml, opts) do
    Eml.Language.Html.Renderer.render(eml, opts)
  end

  defmacro __using__(_opts) do
    quote do
      import Kernel, except: [div: 2]
      import unquote(__MODULE__).Markup
    end
  end
end
