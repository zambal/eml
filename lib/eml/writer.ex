defmodule Eml.Writer do
  use Behaviour

  @type opts :: Keyword.t

  defcallback write(Eml.t, opts) :: { :ok, binary } | Eml.error

end
