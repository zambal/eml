defmodule Eml.Parameter do
  @moduledoc """
  Parameters are placeholders for values in a template or block of `eml`.

  A parameter is created automatically whenever an atom is encountered in a
  block of `eml`. Binding a value to a parameter can be done in several ways
  in Eml. Depending on the use case, you can use `Eml.Template.bind/2`,
  `Eml.Template.bind/3`, `Eml.compile/3`, or `Eml.render/3`.

  ### Examples

      iex> use Eml
      iex> e = eml do: :a_parameter
      [#param:a_parameter]
      iex> Eml.render!(e, a_parameter: "a value")
      "a value"

      iex> e = eml do: p([id: :some_id], :content)
      [#p<%{id: #param:some_id} [#param:content]>]
      iex> t = Eml.compile!(e, some_id: 42)
      #Template<[:content]>
      iex> t = Template.bind(t, content: "some content")
      #Template<BOUND>
      iex> Eml.render!(t)
      "<p id='42'>some content</p>"

  """

  defstruct id: nil, type: :content

  @type id         :: atom
  @type param_type :: :content | :attr
  @type t          ::  %__MODULE__{ id: atom, type: param_type }
end

# Inspect protocol implementation

defimpl Inspect, for: Eml.Parameter do
  import Inspect.Algebra

  def inspect(param, opts) do
    concat ["#param", to_doc(param.id, opts)]
  end
end
