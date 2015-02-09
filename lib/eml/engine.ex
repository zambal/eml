defmodule Eml.Engine do
  @moduledoc false

  def handle_expr(buffer, expr, opts) do
    expr = Macro.prewalk(expr, &EEx.Engine.handle_assign/1)
    quote do
      tmp = unquote(buffer)
      tmp <> Eml.unpack(Eml.render(Eml.encode(unquote(expr)), [], unquote(opts)))
    end
  end
end
