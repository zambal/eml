defmodule Eml.Parameter do
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
