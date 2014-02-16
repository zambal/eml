defmodule Eml.Parameter do
  defrecordp :param, Eml.Parameter, id: nil, type: :content

  @type id         :: atom
  @type param_type :: :content | :attr
  @type t          :: { Eml.Parameter, id, param_type }

  @spec new(id, param_type) :: t
  def new(id, type \\ :content), do: param(id: id, type: type)

  @spec id(t) :: id
  def id(param(id: id)), do: id

  @spec type(t) :: param_type
  def type(param(type: type)), do: type

end

# Inspect protocol implementation

defimpl Inspect, for: Eml.Parameter do
  alias Eml.Parameter, as: Param
  import Inspect.Algebra

  def inspect(param, opts) do
    concat ["#param", to_doc(Param.id(param), opts)]
  end
end
