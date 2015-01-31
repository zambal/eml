defprotocol Eml.Data do
  @moduledoc """
  The Eml Data protocol.

  This protocol is used by `Eml.to_content/3` function to
  convert different Elixir data types to Eml content.

  You can easily implement a protocol implementation
  for a custom type, by defining a `to_eml` function
  that receives the custom type and outputs to `eml`.

  ### Example

      iex> defmodule Customer do
      ...>   defstruct [:name, :email, :phone]
      ...> end
      iex> defimpl Eml.Data, for: Customer do
      ...>   def to_eml(%Customer{name: name, email: email, phone: phone}) do
      ...>     use Eml.Language.HTML
      ...>
      ...>     div [class: "customer"] do
      ...>       div [span("name: "), span(name)]
      ...>       div [span("email: "), span(email)]
      ...>       div [span("phone: "), span(phone)]
      ...>     end
      ...>   end
      ...> end
      iex> div %Customer{name: "Fred", email: "freddy@mail.com", phone: "+31 6 5678 1234"}
      #div<[#div<%{class: "customer"}
       [#div<[#span<["name: "]>, #span<["Fred"]>]>,
        #div<[#span<["email: "]>, #span<["freddy@mail.com"]>]>,
        #div<[#span<["phone: "]>, #span<["+31 6 5678 1234"]>]>]>]>

  Note that you can't directly render a custom type, as the `Eml.Data` protocol is not used during rendering.
  If you want to directly render a custom type, convert it to `eml` content first:
  ```
  %Customer{name: "Fred", email: "freddy@mail.com", phone: "+31 6 5678 1234"} |> Eml.to_content |> Eml.render
  # => "<div class='customer'><div><span>name: </span><span>Fred</span></div><div><span>email: </span><span>freddy@mail.com</span></div><div><span>phone: </span><span>+31 6 5678 1234</span></div></div>"
  ```
  """
  @spec to_eml(Eml.Data.t) :: Eml.t
  def to_eml(data)
end

defimpl Eml.Data, for: Integer do
  def to_eml(data), do: Integer.to_string(data)
end

defimpl Eml.Data, for: Float do
  def to_eml(data), do: Float.to_string(data)
end

defimpl Eml.Data, for: Atom do
  def to_eml(nil),   do: nil
  def to_eml(true),  do: "true"
  def to_eml(false), do: "false"
  def to_eml(param), do: %Eml.Parameter{id: param}
end

defimpl Eml.Data, for: Tuple do
  def to_eml({ :safe, data }) when is_binary(data), do: { :safe, data }
  def to_eml(unsupported_tuple) do
    raise Protocol.UndefinedError, protocol: Eml.Data, value: unsupported_tuple
  end
end

defimpl Eml.Data, for: [BitString, Eml.Element, Eml.Parameter, Eml.Template] do
  def to_eml(data), do: data
end
