defmodule Eml.Template do
  alias Eml.Readable, as: Read
  alias __MODULE__, as: M

  defstruct chunks: [], params: [], bindings: []

  @type chunks   :: [binary | Eml.Parameter.t]
  @type params   :: [{ Eml.Parameter.id, integer }]
  @type bindings :: [{ Eml.Parameter.id, [Eml.element] }]
  @type t        :: %M{ chunks: chunks, params: params, bindings: bindings }

  @lang Eml.Language.Native

  @spec get(t, Eml.Parameter.id) :: Read.t | nil
  def get(%M{bindings: bindings}, param_id)
  when is_atom(param_id), do: Keyword.get(bindings, param_id, [])

  @spec set(t, Eml.Parameter.id, Eml.data) :: t
  def set(%M{bindings: bindings} = t, param_id, data)
  when is_atom(param_id) do
    %M{t| bindings: Keyword.put(bindings, param_id, Eml.read(data, @lang))}
  end

  @spec unset(t, Eml.Parameter.id) :: Read.t | nil
  def unset(%M{bindings: bindings} = t, param_id)
  when is_atom(param_id), do: %M{t| bindings: Keyword.delete(bindings, param_id)}

  @spec bind(t, bindings) :: t
  def bind(%M{bindings: current} = t, new) do
    new = for { id, data } <- new do
      readed = if is_list(data) do
                 for d <- data, do: Eml.read(d, @lang)
               else
                 Eml.read(data, @lang)
               end
      { id, get(t, id) ++ readed }
    end
    %M{t| bindings: Keyword.merge(current, new)}
  end

  @spec bind(t, Eml.Parameter.id, Eml.data) :: t
  def bind(t, param_id, data)
  when is_atom(param_id), do: bind(t, [{ param_id, data }])

  @spec unbind(t, bindings) :: t
  def unbind(%M{bindings: current} = t, unbinds) do
    removed = for { id, data } <- unbinds do
      readed = for d <- data, do: Eml.read(d, @lang)
      { id, get(t, id) -- readed }
    end
    %M{t| bindings: Keyword.merge(current, removed)}
  end

  @spec unbind(t, Eml.Parameter.id, Eml.data) :: t
  def unbind(t, param_id, data)
  when is_atom(param_id), do: unbind(t, [{ param_id, data }])

  @spec pop(bindings, Eml.Parameter.id) :: { Eml.element | nil, bindings }
  def pop(bindings, param_id) when is_atom(param_id) do
    binding = Keyword.get(bindings, param_id, [])
    if binding === [] do
      { nil, bindings }
    else
      [element | rest] = binding
      { element, Keyword.put(bindings, param_id, rest) }
    end
  end

  @spec pop(t, Eml.Parameter.id) :: { Eml.element | nil, t }
  def pop(%M{bindings: bindings} = t, param_id) when is_atom(param_id) do
    { element, bindings } = pop(bindings, param_id)
    { element, %M{t| bindings: bindings} }
  end

  @spec unbound(t) :: params
  def unbound(%M{bindings: bindings, params: params}) do
    Enum.reduce(params, [], fn { id, count }, acc ->
      case count - length(Keyword.get(bindings, id, [])) do
        0 -> acc
        n -> [{ id, n } | acc]
      end
    end) |> :lists.reverse()
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
    bindstat = case Eml.Template.unbound(t) do
                 []      -> "BOUND"
                 unbound -> to_doc(unbound, opts)
               end
    concat ["#Template", "<", bindstat, ">"]
  end
end
