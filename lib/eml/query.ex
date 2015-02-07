defmodule Eml.Query do

  @doc """
  Selects nodes from arbritary content.

  It will traverse the complete eml tree, so all nodes are
  evaluated. There is however currently no way to select quoted
  expressions.

  Nodes are matched depending on the provided options.

  Those options can be:

  * `:tag` - match element by tag (`atom`)
  * `:id` - match element by id (`binary`)
  * `:class` - match element by class (`binary`)
  * `:pat` - match binary content by regular expression (`RegEx.t`)
  * `:parent` - when set to true, selects the parent node
    of the matched node (`boolean`)

  When `:tag`, `:id`, or `:class` are combined, only elements are
  selected that satisfy all conditions.

  When the `:pat` options is used, `:tag`, `:id` and `:class` will
  be ignored.


  ### Examples:

      iex> e = div do
      ...>   span [id: "inner1", class: "inner"], "hello "
      ...>   span [id: "inner2", class: "inner"], "world"
      ...> end
      #div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
       #span<%{id: "inner2", class: "inner"} ["world"]>]>
      iex> Query.select(e, id: "inner1")
      [#span<%{id: "inner1", class: "inner"} ["hello "]>]
      iex> Query.select(e, class: "inner")
      [#span<%{id: "inner1", class: "inner"} ["hello "]>,
       #span<%{id: "inner2", class: "inner"} ["world"]>]
      iex> Query.select(e, class: "inner", id: "test")
      []
      iex> Query.select(e, pat: ~r/h.*o/)
      ["hello "]
      iex> Query.select(e, pat: ~r/H.*o/, parent: true)
      [#span<%{id: "inner1", class: "inner"} ["hello "]>]

  """
  @spec select(enumerable) :: [t]
  def select(eml, opts \\ [])

  def select(content, opts) when is_list(content) do
    Enum.flat_map(content, &select(&1, opts))
  end
  def select(node, opts) do
    tag            = opts[:tag] || :any
    id             = opts[:id] || :any
    class          = opts[:class] || :any
    pat            = opts[:pat]
    select_parent? = opts[:parent] || false
    select_fun     =
      if select_parent? do
        if pat,
          do: &Element.child_pat_match?(&1, pat),
        else: &Element.child_match?(&1, tag, id, class)
      else
        if pat,
          do: &Element.pat_match?(&1, pat),
        else: &Element.match?(&1, tag, id, class)
      end
    enum = case node do
             %Element{} -> node
             _other     -> [node]
           end
    Enum.filter(enum, select_fun)
  end

  @doc """
  Returns true if there's at least one node matches
  the provided options, returns false otherwise.

  In other words, returns true when the same select query
  would return a non-empty list.

  See `select/3` for a description of the provided options.

  ### Examples:

      iex> e = div do
      ...>   span [id: "inner1", class: "inner"], "hello "
      ...>   span [id: "inner2", class: "inner"], "world"
      ...> end
      #div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
       #span<%{id: "inner2", class: "inner"} ["world"]>]>
      iex> Query.member?(e, id: "inner1")
      true
      iex> Query.member?(e, class: "inner", id: "test")
      false
      iex> Query.member?(e, pat: ~r/h.*o/)
      true

  """
  @spec member?(enumerable, Keyword.t) :: boolean
  def member?(eml, opts) do
    case select(eml, opts) do
      [] -> false
      _  -> true
    end
  end
end
