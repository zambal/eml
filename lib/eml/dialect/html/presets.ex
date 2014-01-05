defmodule Eml.Dialect.Html.Presets do
  use Eml

  defmarkup keyword(kw, sep // ":") do
    lc { k, v } inlist kw do
      div [class: "keyword-kv"] do
        span [class: "keyword-k"], atom_to_binary(k)
        span [class: "keyword-sep"], sep
        span [class: "keyword-v"], v
      end
    end
  end
end