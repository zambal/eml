defmodule Eml.HTML.Engine do
  @moduledoc false

  use EEx.Engine

  def handle_expr(buffer, _mark, expr, opts \\ []) do
    Eml.Engine.handle_expr(buffer, expr, Dict.merge([renderer: Eml.HTML.Renderer], opts))
  end
end
