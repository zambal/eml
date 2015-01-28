defmodule Eml.Language.Html.Elements do
  @moduledoc """
  This is the container module of all the generated HTML element macro's.
  
  To import all these macro's into current scope, invoke `use Eml.Language.Html`
  """

  use Eml.Element.Generator, tags: [:html, :head, :title, :base, :link, :meta, :style,
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
  @moduledoc """
  This module implements the `Eml.Language` behaviour and
  contains a `use` macro for importing all the generated
  element macro's in to the current scope.
  """
  @behaviour Eml.Language

  @doc false
  def element?(), do: true

  @doc false
  def parse(data, type) do
    Eml.Language.Html.Parser.parse(data, type)
  end

  @doc false
  def render(eml, opts) do
    Eml.Language.Html.Renderer.render(eml, opts)
  end

  @doc """
  Import HTML element macro's

  Invoking `use Eml.Language.Html` translates to:
  ```elixir
  alias Eml.Element
  alias Eml.Template
  import Eml.Template, only: [bind: 2]
  import Kernel, except: [div: 2]
  import Eml.Language.Html.Elements
  ```

  Note that it unimports `Kernel.div/2` to avoid clashing with the `div` element macro.
  """
  defmacro __using__(_opts) do
    quote do
      unquote(Eml.default_alias_and_imports)
      import Kernel, except: [div: 2]
      import unquote(__MODULE__).Elements
    end
  end
end
