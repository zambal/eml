defmodule Eml.Mixfile do
  use Mix.Project

  def project do
    [ app: :eml,
      version: "0.9.0-dev",
      name: "Eml",
      source_url: "https://github.com/zambal/eml",
      homepage_url: "https://github.com/zambal/eml",
      deps: deps(),
      description: description(),
      package: package() ]
  end

  def application do
    []
  end

  def deps do
    [ { :ex_doc, "~> 0.9", only: :docs },
      { :earmark, "~> 0.1", only: :docs } ]
  end

  defp description do
    """
    Eml makes markup a first class citizen in Elixir. It provides a
    flexible and modular toolkit for generating, parsing and
    manipulating markup. It's main focus is html, but other markup
    languages could be implemented as well.
    """
  end

  defp package do
    [ files: ["lib", "priv", "mix.exs", "README*", "readme*", "LICENSE*", "license*", "CHANGELOG*"],
      contributors: ["Vincent Siliakus"],
      licenses: ["Apache 2.0"],
      links: %{
        "GitHub" => "https://github.com/zambal/eml",
        "Walkthrough" => "https://github.com/zambal/eml/blob/master/README.md",
        "Documentation" => "https://hexdocs.pm/eml/"
      } ]
  end
end
