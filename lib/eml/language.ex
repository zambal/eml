defmodule Eml.Language do
  use Behaviour

  @type type :: atom
  @type opts :: Keyword.t

  defcallback markup?() :: true | false

  defcallback read(Eml.Readable.t, type) :: Eml.t | Eml.error
  defcallback write(Eml.t, opts) :: { :ok, Eml.Readable.t } | Eml.error
end
