defmodule Eml.Language do
  use Behaviour

  @type type :: atom
  @type opts :: Keyword.t

  defcallback markup?() :: true | false

  defcallback parse(Eml.Parsable.t, type) :: Eml.t | Eml.error
  defcallback render(Eml.t, opts) :: { :ok, Eml.Parsable.t } | Eml.error
end
