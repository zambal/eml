defmodule Eml.Mixfile do
  use Mix.Project

  def project do
    [ app: :eml,
      version: "0.3.0",
      description: description,
      package: package ]
  end

  def application do
    []
  end

  defp description do
    """
    Eml stands for Elixir Markup Language. It provides a flexible and
    modular toolkit for generating, parsing and manipulating markup,
    written in the Elixir programming language. It's main focus is
    html, but other markup languages could be implemented as well.
    """
  end

  defp package do
    [ files: ["lib", "priv", "mix.exs", "README*", "readme*", "LICENSE*", "license*"],
      contributors: ["Vincent Siliakus"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/zambal/eml"} ]
  end

end
