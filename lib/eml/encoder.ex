defprotocol Eml.Encoder do
  @moduledoc """
  The Eml Encoder protocol.

  This protocol is used by Eml's compiler to convert different Elixir
  data types to it's `Eml.Compiler.chunk` type.

  Chunks can be of the type `String.t`, `{ :safe, String.t }`,
  `Eml.Element.t`, or `Macro.t`, so any implementation of the
  `Eml.Encoder` protocol needs to return one of these types.

  Eml implements the following types by default:

  `Integer`, `Float`, `Atom`, `Tuple`, `BitString` and `Eml.Element`

  You can easily implement a protocol implementation for a custom
  type, by defining an `encode` function that receives the custom type
  and outputs to `Eml.Compiler.chunk`.

  ### Example

      iex> defmodule Customer do
      ...>   defstruct [:name, :email, :phone]
      ...> end
      iex> defimpl Eml.Encoder, for: Customer do
      ...>   def encode(%Customer{name: name, email: email, phone: phone}) do
      ...>     use Eml.HTML
      ...>
      ...>     div [class: "customer"] do
      ...>       div [span("name: "), span(name)]
      ...>       div [span("email: "), span(email)]
      ...>       div [span("phone: "), span(phone)]
      ...>     end
      ...>   end
      ...> end
      iex> c = %Customer{name: "Fred", email: "freddy@mail.com", phone: "+31 6 5678 1234"}
      %Customer{email: "freddy@mail.com", name: "Fred", phone: "+31 6 5678 1234"}
      iex> Eml.Encoder.encode c
      #div<%{class: "customer"}
      [#div<[#span<"name: ">, #span<"Fred">]>,
       #div<[#span<"email: ">, #span<"freddy@mail.com">]>,
       #div<[#span<"phone: ">, #span<"+31 6 5678 1234">]>]>
      iex> Eml.render c
      "<div class='customer'><div><span>name: </span><span>Fred</span></div><div><span>email: </span><span>freddy@mail.com</span></div><div><span>phone: </span><span>+31 6 5678 1234</span></div></div>"

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
  def encode(data),  do: Atom.to_string(data)
end

defimpl Eml.Encoder, for: Tuple do
  def encode({ :safe, data }) do
    if is_binary(data) do
      { :safe, data }
    else
      raise Protocol.UndefinedError, protocol: Eml.Encoder, value: { :safe, data }
    end
  end
  def encode(data) do
    if Macro.validate(data) == :ok do
      data
    else
      raise Protocol.UndefinedError, protocol: Eml.Encoder, value: data
    end
  end
end

defimpl Eml.Encoder, for: [BitString, Eml.Element] do
  def encode(data), do: data
end
