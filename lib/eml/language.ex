defmodule Eml.Language do
  @moduledoc """
  Defines the Eml.Language behaviour.

  Eml ships currentlu with two implementations:
  `Eml.Language.Native` and `Eml.Language.Html`.
  """

  use Behaviour

  @type type :: atom
  @type opts :: Keyword.t

  defcallback element?() :: true | false

  defcallback parse(Eml.Parsable.t, type) :: Eml.t | Eml.error
  defcallback render(Eml.t, opts) :: { :ok, Eml.Parsable.t } | Eml.error
end
