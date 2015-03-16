defprotocol Eml.Encoder do
  @moduledoc """
  The Eml Encoder protocol.

  This protocol is used by `Eml.encode/3` function to
  convert different Elixir data types to Eml content.

  You can easily implement a protocol implementation
  for a custom type, by defining a `encode` function
  that receives the custom type and outputs to `eml`.

  ### Example

      iex> defmodule Customer do
      ...>   defstruct [:name, :email, :phone]
      ...> end
      iex> defimpl Eml.Encoder, for: Customer do
      ...>   def encode(%Customer{name: name, email: email, phone: phone}) do
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

  Note that you can't directly render a custom type, as the `Eml.Encoder` protocol is not used during rendering.
  If you want to directly render a custom type, convert it to `eml` content first:
  ```
  %Customer{name: "Fred", email: "freddy@mail.com", phone: "+31 6 5678 1234"} |> Eml.encode |> Eml.render
  # => "<div class='customer'><div><span>name: </span><span>Fred</span></div><div><span>email: </span><span>freddy@mail.com</span></div><div><span>phone: </span><span>+31 6 5678 1234</span></div></div>"
  ```
  """
  @spec encode(Eml.Encoder.t) :: Eml.t
  def encode(data)
end

defimpl Eml.Encoder, for: Integer do
  def encode(data), do: Integer.to_string(data)
end

defimpl Eml.Encoder, for: Float do
  def encode(data), do: Float.to_string(data)
end

defimpl Eml.Encoder, for: Atom do
  def encode(nil),   do: nil
  def encode(true),  do: "true"
  def encode(false), do: "false"
  def encode(assign), do: { :quoted, [quote do: @unquote(Macro.var(assign, __MODULE__))] }
end

defimpl Eml.Encoder, for: Tuple do
  def encode({ :safe, data }), do: { :safe, data }
  def encode({ :quoted, quoted }), do: { :quoted, List.wrap(quoted) }
  def encode(data) do
    if Macro.validate(data) == :ok do
      { :quoted, List.wrap(data) }
    else
      raise Protocol.UndefinedError, protocol: Eml.Encoder, value: data
    end
  end
end

defimpl Eml.Encoder, for: [BitString, Eml.Element] do
  def encode(data), do: data
end
