defmodule Eml.Parameter do
  defrecordp :param, Eml.Parameter, id: nil, type: :content, ilevel: 0

  @type id         :: atom
  @type param_type :: :content | :attr
  @type ilevel     :: integer
  @type t          :: { Eml.Parameter, id, param_type, ilevel }

  @spec new(id, param_type, ilevel) :: t
  def new(id, type // :content, ilevel // 0),
  do: param(id: id, type: type, ilevel: ilevel)

  @spec id(t) :: id
  def id(param(id: id)), do: id

  @spec type(t) :: param_type
  def type(param(type: type)), do: type

  @spec ilevel(t) :: ilevel
  def ilevel(param(ilevel: ilevel)), do: ilevel

  @spec ilevel(t, ilevel) :: t
  def ilevel(param, ilevel), do: param(param, ilevel: ilevel)

end

# Inspect protocol implementation

defimpl Inspect, for: Eml.Parameter do
  alias Eml.Parameter, as: Param
  import Inspect.Algebra

  def inspect(param, opts) do
    concat ["#param", Kernel.inspect(Param.id(param), opts)]
  end
end
