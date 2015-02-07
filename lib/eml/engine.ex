defmodule Eml.Engine do
  @moduledoc false

  def handle_expr(buffer, expr, renderer) do
    expr = Macro.prewalk(expr, &EEx.Engine.handle_assign/1)
    quote do
      tmp = unquote(buffer)
      tmp <> Eml.unpack(Eml.render(Eml.encode(unquote(expr)), [], renderer: unquote(renderer)))
    end
  end
end
