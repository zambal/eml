defmodule Eml.Template.Record do
  @moduledoc false

  defmacro __using__(_) do
    quote do
      defrecordp :templ, Eml.Template, chunks: [], params: [], bindings: []
    end
  end

end

defmodule Eml.Template do
  use Eml.Template.Record
  alias Eml.Readable, as: Read

  @type chunks   :: [binary | Eml.Parameter.t]
  @type params   :: [{ Eml.Parameter.id, integer }]
  @type bindings :: [{ Eml.Parameter.id, [Eml.element] }]
  @type t        :: { Eml.Template, chunks, params, bindings }

  @lang Eml.Language.Native

  @spec params(t) :: params
  def params(templ(params: params)), do: params

  @spec bindings(t) :: bindings
  def bindings(templ(bindings: bindings)), do: bindings

  @spec bindings(t, bindings) :: t
  def bindings(t, bindings), do: templ(t, bindings: bindings)

  @spec get(t, Eml.Parameter.id) :: Read.t | nil
  def get(templ(bindings: bindings), param_id)
  when is_atom(param_id), do: Keyword.get(bindings, param_id, [])

  @spec set(t, Eml.Parameter.id, Eml.data) :: t
  def set(templ(bindings: bindings) = t, param_id, data)
  when is_atom(param_id) do
    templ(t, bindings: Keyword.put(bindings, param_id, Eml.read(data, @lang)))
  end

  @spec unset(t, Eml.Parameter.id) :: Read.t | nil
  def unset(templ(bindings: bindings) = t, param_id)
  when is_atom(param_id), do: templ(t, bindings: Keyword.delete(bindings, param_id))

  @spec bind(t, bindings) :: t
  def bind(templ(bindings: current) = t, new) do
    new = lc { id, data } inlist new do
      readed = if is_list(data) do
                 lc d inlist data, do: Eml.read(d, @lang)
               else
                 Eml.read(data, @lang)
               end
      { id, get(t, id) ++ readed }
    end
    templ(t, bindings: Keyword.merge(current, new))
  end

  @spec bind(t, Eml.Parameter.id, Eml.data) :: t
  def bind(t, param_id, data)
  when is_atom(param_id), do: bind(t, [{ param_id, data }])

  @spec unbind(t, bindings) :: t
  def unbind(templ(bindings: current) = t, unbinds) do
    removed = lc { id, data } inlist unbinds do
      readed = lc d inlist data, do: Eml.read(d, @lang)
      { id, get(t, id) -- readed }
    end
    templ(t, bindings: Keyword.merge(current, removed))
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
  def pop(templ(bindings: bindings) = t, param_id) when is_atom(param_id) do
    { element, bindings } = pop(bindings, param_id)
    { element, templ(t, bindings: bindings) }
  end

  @spec unbound(t) :: params
  def unbound(templ(bindings: bindings, params: params)) do
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
                 unbound -> Kernel.inspect(unbound, opts)
               end
    concat ["#Template", "<", bindstat, ">"]
  end
end
