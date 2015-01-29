defmodule Eml.Language do
  @moduledoc false

  use Behaviour

  @type type :: atom
  @type opts :: Keyword.t

  defcallback element?() :: true | false

  defcallback parse(String.t) :: [Eml.t] | Eml.error
  defcallback render(Eml.t, opts) :: { :ok, String.t } | Eml.error
end
