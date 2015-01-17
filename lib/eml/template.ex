defmodule Eml.Template do
  alias __MODULE__, as: M

  defstruct chunks: [], bindings: []

  @type chunks   :: [binary | Eml.Parameter.t]
  @type bindings :: [{ Eml.Parameter.id, Eml.element }]
  @type t        :: %M{ chunks: chunks, bindings: bindings }

  @lang Eml.Language.Native


  @spec bind(t, bindings) :: t
  def bind(%M{bindings: current} = t, new) do
    %M{t| bindings: Keyword.merge(current, new)}
  end

  @spec bind(t, Eml.Parameter.id, Eml.data) :: t
  def bind(t, param_id, data)
  when is_atom(param_id), do: bind(t, [{ param_id, data }])

  @spec unbind(t, Eml.Parameter.id | [Eml.Parameter.id]) :: t
  def unbind(t, param_id)
  when is_atom(param_id), do: unbind(t, [param_id])

  def unbind(%M{bindings: bindings} = t, param_ids) do
    %M{t| bindings: Keyword.drop(bindings, param_ids)}
  end

  @spec unbound(t) :: [Eml.Parameter.id]
  def unbound(%M{chunks: chunks, bindings: bindings}) do
    keys = Keyword.keys(bindings)
    (for %Eml.Parameter{id: id} <- chunks, not id in keys, do: id)
    |> Enum.uniq()
  end

  @spec bound?(t) :: boolean
  def bound?(t) do
    case unbound(t) do
      [] -> true
      _  -> false
    end
  end
end

# Inspect protocol implementation

defimpl Inspect, for: Eml.Template do
  import Inspect.Algebra

  def inspect(t, opts) do
    unbound = case Eml.Template.unbound(t) do
                 []      -> "BOUND"
                 unbound -> to_doc(unbound, opts)
               end
    concat ["#Template", "<", unbound, ">"]
  end
end
