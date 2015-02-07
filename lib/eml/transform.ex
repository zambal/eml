defmodule Eml.Transform do

  @doc """
  Recursively transforms `eml` content.

  This is the most low level operation provided by Eml for manipulating
  eml nodes. For example, `update/3` and `remove/2` are implemented by
  using this function.

  It accepts any eml and traverses all nodes of the provided eml tree.
  The provided transform function will be evaluated for every node `transform/3`
  encounters. Parent nodes will be transformed before their children. Child nodes
  of a parent will be evaluated before moving to the next sibling.

  When the provided function returns `nil`, the node will
  be removed from the eml tree. Any other returned value will be
  evaluated by `Eml.encode/3` in order to guarantee valid eml.

  Note that because parent nodes are evaluated before their children,
  no children will be evaluated if the parent is removed.

  ### Examples:

      iex> e = div do
      ...>   span [id: "inner1", class: "inner"], "hello "
      ...>   span [id: "inner2", class: "inner"], "world"
      ...> end
      #div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
       #span<%{id: "inner2", class: "inner"} ["world"]>]>
      iex> transform(e, fn x -> if Element.has?(x, tag: :span), do: "matched", else: x end)
      [#div<["matched", "matched"]>]
      iex> transform(e, fn x ->
      ...> IO.puts(inspect x)
      ...> x end)
      #div<[#span<%{id: "inner1", class: "inner"} ["hello "]>, #span<%{id: "inner2", class: "inner"} ["world"]>]>
      #span<%{id: "inner1", class: "inner"} ["hello "]>
      "hello "
      #span<%{id: "inner2", class: "inner"} ["world"]>
      "world"
      [#div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
        #span<%{id: "inner2", class: "inner"} ["world"]>]>]

  """
  @spec transform(transformable, (t -> Eml.Encoder.t)) :: transformable | nil
  def transform(eml, fun) when is_list(eml) do
    for node <- eml, t = transform(node, fun), do: t
  end
  def transform(node, fun) do
    node = fun.(node) |> Encoder.encode()
    if element?(node) do
      %Element{node| content: transform(node.content, fun)}
    else
      node
    end
  end

  @doc """
  Adds content to matched elements.

  It traverses and returns the complete eml tree.
  Nodes are matched depending on the provided options.

  Those options can be:

  * `:tag` - match element by tag (`atom`)
  * `:id` - match element by id (`binary`)
  * `:class` - match element by class (`binary`)
  * `:at` -  add new content at begin or end of existing
    content, default is `:end` (`:begin | :end`)

  When `:tag`, `:id`, or `:class` are combined, only elements are
  selected that satisfy all conditions.


  ### Examples:

      iex> e = div do
      ...>   span [id: "inner1", class: "inner"], "hello "
      ...>   span [id: "inner2", class: "inner"], "world"
      ...> end
      #div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
       #span<%{id: "inner2", class: "inner"} ["world"]>]>
      iex> Transform.add(e, "dear ", id: "inner1")
      [#div<[#span<%{id: "inner1", class: "inner"} ["hello dear "]>,
        #span<%{id: "inner2", class: "inner"} ["world"]>]>]
      iex> Transform.add(e, "__", class: "inner", at: :begin)
      [#div<[#span<%{id: "inner1", class: "inner"} ["__hello "]>,
        #span<%{id: "inner2", class: "inner"} ["__world"]>]>]
      iex> Transform.add(e, span("!"), tag: :div) |> Eml.render()
      "<div><span id='inner1' class='inner'>hello </span><span id='inner2' class='inner'>world</span><span>!</span></div>"

  """
  @spec add(transformable, Eml.Encoder.t, Keyword.t) :: transformable
  def add(eml, data, opts \\ []) do
    tag     = opts[:tag] || :any
    id      = opts[:id] || :any
    class   = opts[:class] || :any
    add_fun = &(if Element.match?(&1, tag, id, class), do: Element.add(&1, data, opts), else: &1)
    transform(eml, add_fun)
  end

  @doc """
  Updates matched nodes.

  When nodes are matched, the provided function will be evaluated
  with the matched node as argument.

  When the provided function returns `nil`, the node will
  be removed from the eml tree. Any other returned value will be
  evaluated by `Eml.encode/3` in order to guarantee valid eml.

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
      iex> Transform.update(e, fn m -> Element.id(m, "outer") end, tag: :div)
      [#div<%{id: "outer"}
       [#span<%{id: "inner1", class: "inner"} ["hello "]>,
        #span<%{id: "inner2", class: "inner"} ["world"]>]>]
      iex> Transform.update(e, fn m -> Element.id(m, "outer") end, id: "inner2", parent: true)
      [#div<%{id: "outer"}
       [#span<%{id: "inner1", class: "inner"} ["hello "]>,
        #span<%{id: "inner2", class: "inner"} ["world"]>]>]
      iex> Transform.update(e, fn s -> String.upcase(s) end, pat: ~r/.+/) |> Eml.render()
      "<div><span id='inner1' class='inner'>HELLO </span><span id='inner2' class='inner'>WORLD</span></div>"

  """
  @spec update(transformable, (t -> Eml.Encoder.t), Keyword.t) :: transformable
  def update(eml, fun, opts \\ []) do
    tag            = opts[:tag] || :any
    id             = opts[:id] || :any
    class          = opts[:class] || :any
    pat            = opts[:pat]
    update_parent? = opts[:parent] || false
    update_fun     =
      if update_parent? do
        if pat do
          &(if Element.child_pat_match?(&1, pat), do: fun.(&1), else: &1)
        else
          &(if Element.child_match?(&1, tag, id, class), do: fun.(&1), else: &1)
        end
      else
        if pat do
          &(if Element.pat_match?(&1, pat), do: fun.(&1), else: &1)
        else
          &(if Element.match?(&1, tag, id, class), do: fun.(&1), else: &1)
        end
      end
    transform(eml, update_fun)
  end

  @doc """
  Removes matched nodes from the eml tree.

  See `update/3` for a description of the provided options.

  ### Examples:

      iex> e = div do
      ...>   span [id: "inner1", class: "inner"], "hello "
      ...>   span [id: "inner2", class: "inner"], "world"
      ...> end
      #div<[#span<%{id: "inner1", class: "inner"} ["hello "]>,
       #span<%{id: "inner2", class: "inner"} ["world"]>]>
      iex> Transform.remove(e, tag: :div)
      []
      iex> Transform.remove(e, id: "inner1")
      [#div<[#span<%{id: "inner2", class: "inner"} ["world"]>]>]
      iex> Transform.remove(e, pat: ~r/.+/)
      [#div<[#span<%{id: "inner1", class: "inner"}>,
        #span<%{id: "inner2", class: "inner"}>]>]

  """
  @spec remove(transformable, Keyword.t) :: transformable
  def remove(eml, opts \\ []) do
    tag            = opts[:tag] || :any
    id             = opts[:id] || :any
    class          = opts[:class] || :any
    pat            = opts[:pat]
    remove_parent? = opts[:parent] || false
    remove_fun     =
      if remove_parent? do
        if pat do
          &(if Element.child_pat_match?(&1, pat), do: nil, else: &1)
        else
          &(if Element.child_match?(&1, tag, id, class), do: nil, else: &1)
        end
      else
        if pat do
          &(if Element.pat_match?(&1, pat), do: nil, else: &1)
        else
          &(if Element.match?(&1, tag, id, class), do: nil, else: &1)
        end
      end
    transform(eml, remove_fun)
  end
end
