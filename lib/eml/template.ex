defmodule Eml.Template do
  @moduledoc """
  Templates in Eml are simple structures that contain rendererd chunks of `eml`,
  optionally interleaved with parameters.

  A template is created when you compile some block of `eml`. Templates can
  also be precompiled at compile time by using the `Eml.precompile/2` macro.

  ### Example:

      iex> use Eml
      iex> t = eml do
      ...>   div class: "photo" do
      ...>     div do
      ...>       img [src: :url, alt: :title]
      ...>       p [], :title
      ...>     end
      ...>   end
      ...> end |> Eml.compile
      #Template<[:title, :url]>
      iex> t = Template.bind(t, url: "http://i.imgur.com/4xPWp.jpg")
      #Template<[:title]>
      iex> Eml.render!(t, title: "Little duck")
      "<div class='photo'><div><img alt='Little duck' src='http://i.imgur.com/4xPWp.jpg'/><p>Little duck</p></div></div>"

  """

  alias __MODULE__, as: M

  defstruct chunks: [], bindings: []

  @type chunks   :: [binary | Eml.Parameter.t]
  @type bindings :: [{ Eml.Parameter.id, Eml.data }]
  @type t        :: %M{ chunks: chunks, bindings: bindings }

  @lang Eml.Language.Native

  @doc """
  Binds values to parameters by providing a Keyword list where
  the Keyword keys are parameter ids.
  """
  @spec bind(t, bindings) :: t
  def bind(%M{bindings: current} = t, new) do
    %M{t| bindings: Keyword.merge(current, new)}
  end

  @doc """
  Binds a value to parameters by providing a parameter ids
  and value.
  """
  @spec bind(t, Eml.Parameter.id, Eml.data) :: t
  def bind(t, param_id, data)
  when is_atom(param_id), do: bind(t, [{ param_id, data }])

  @doc """
  Unbinds a previously binded value by providing a parameter id.

  Note that it's not possible to unbind values after a
  template is compiled.
  """
  @spec unbind(t, Eml.Parameter.id | [Eml.Parameter.id]) :: t
  def unbind(t, param_id)
  when is_atom(param_id), do: unbind(t, [param_id])

  @doc """
  Unbinds previously binded values by providing a list of
  parameter ids.

  Note that it's not possible to unbind values after a
  template is compiled.
  """
  def unbind(%M{bindings: bindings} = t, param_ids) do
    %M{t| bindings: Keyword.drop(bindings, param_ids)}
  end

  @doc """
  Lists all parameter ids that are not yet bound to a value.

  ### Example
      iex> use Eml
      iex> t = Eml.compile!(eml do: div([id: :id], :content))
      #Template<[:id, :content]>
      iex> Template.unbound(t)
      [:id, :content]
      iex> t = Template.bind(t, :id, "some_id")
      #Template<[:content]>
      iex> Template.unbound(t)
      [:content]

  """
  @spec unbound(t) :: [Eml.Parameter.id]
  def unbound(%M{chunks: chunks, bindings: bindings}) do
    keys = Keyword.keys(bindings)
    (for %Eml.Parameter{id: id} <- chunks, not id in keys, do: id)
    |> Enum.uniq()
  end

  @doc """
  Checks if all parameters in the template are bound.

  ### Example
      iex> use Eml
      iex> t = Eml.compile!(eml do: div([id: :id], :content))
      #Template<[:id, :content]>
      iex> Template.bound?(t)
      false
      iex> t = Template.bind(t, id: "some_id", content: "some content")
      iex> Template.bound?(t)
      true

  """
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
