defmodule Eml.HTML.Engine do
  @moduledoc false

  use EEx.Engine

  def handle_expr(buffer, _mark, expr) do
    Eml.Engine.handle_expr(buffer, expr, Eml.HTML.Renderer)
  end
end
