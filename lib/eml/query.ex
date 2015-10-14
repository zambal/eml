defmodule Eml.Query.Helper do
  @moduledoc false
  alias Eml.Element

  def do_transform(_node, :node, value) do
    value
  end
  def do_transform(%Element{attrs: attrs} = node, { :attrs, key }, value) do
    %Element{node|attrs: Map.put(attrs, key, value)}
  end
  def do_transform(%Element{} = node, key, value) do
    Map.put(node, key, value)
  end
  def do_transform(node, key, _value) do
    raise Eml.QueryError, message: "can only set key `#{inspect key}` on an element node, got: #{inspect node}"
  end

  def do_add(%Element{content: content} = node, expr, op) do
    content = if op == :insert do
                List.wrap(expr) ++ List.wrap(content)
              else
                List.wrap(content) ++ List.wrap(expr)
              end
    %Element{node|content: content}
  end
  def do_add(node, _expr, op) do
    raise Eml.QueryError,
    message: "can only #{op} with an element node, got: #{inspect node}"
  end

  def do_collect(op, acc, key, expr) do
    case op do
      :put    -> Map.put(acc, key, expr)
      :insert -> Map.update(acc, key, List.wrap(expr), &(List.wrap(expr) ++ List.wrap(&1)))
      :append -> Map.update(acc, key, List.wrap(expr), &(List.wrap(&1) ++ List.wrap(expr)))
    end
  end
end

defmodule Eml.Query do
  @moduledoc """
  Provides a DSL for retrieving and manipulating eml.

  Queries can be used on its own, but they are best used together with
  `Eml.transform/2`, `Eml.collect/3` and the `Enumerable` protocol. Using them
  often results in simpler and easier to read code. One of the main conveniences
  of queries is that you have easy access to all fields of an element. For
  example, all queries support a `where` expression. Inside a `where` expression
  you can automatically use the variables `node`, `tag`, `attrs`,
  `attrs.{field}`, `content` and `type`. Lets illustrate this with an example of
  `node_match?/2`, the simplest query Eml provides:

      iex> use Eml
      iex> import Eml.Query
      iex> node = div [class: "test"], "Hello world"
      #div<%{class: "test"} "Hello world">

      iex> node_match? node, where: attrs.class == "test"
      true

      iex> node_match? node, where: tag in [:div, :span]
      true

      iex> node_match? node, where: tag == :span or is_binary(node)
      false

  Queries can be divided in two groups: queries that help collecting data from
  eml nodes and queries that help transform eml nodes.

  ## Transform queries

    * `put`: puts new data into a node
    * `update`: updates data in a node
    * `drop`: removes a node
    * `insert`: insert new content into a node
    * `append`: appends new content to a node

  ### Transfrom examples

      iex> use Eml
      iex> import Eml.Query
      iex> node = div(42)
      #div<42>

      iex> put node, "Hello World", in: content, where: content == 42
      #div<"Hello World">

      iex> insert node, 21, where: tag == :div
      #div<[21, 42]>

      iex> node = html do
      ...>   head do
      ...>     meta charset: "UTF-8"
      ...>   end
      ...>   body do
      ...>     div class: "person" do
      ...>       div [class: "person-name"], "mike"
      ...>       div [class: "person-age"], 23
      ...>     end
      ...>     div class: "person" do
      ...>       div [class: "person-name"], "john"
      ...>       div [class: "person-age"], 42
      ...>     end
      ...>   end
      ...> end

      iex> Eml.transform(node, fn n ->
      ...>   n
      ...>   |> drop(where: tag == :head)
      ...>   |> update(content, with: &(&1 + 1), where: attrs.class == "person-age")
      ...>   |> update(content, with: &String.capitalize/1, where: attrs.class == "person-name")
      ...>   |> insert(h1("Persons"), where: tag == :body)
      ...>   |> append(div([class: "person-status"], "friend"), where: attrs.class == "person")
      ...> end)
      #html<[#body<[#h1<"Persons">, #div<%{class: "person"}
        [#div<%{class: "person-name"} "Mike">, #div<%{class: "person-age"} 24>,
         #div<%{class: "person-status"} "friend">]>, #div<%{class: "person"}
        [#div<%{class: "person-name"} "John">, #div<%{class: "person-age"} 43>,
         #div<%{class: "person-status"} "friend">]>]>]>


  ## Collect queries

    * `put`: get data from a node and put it in a map
    * `insert` get data from a node and insert it in a map
    * `append` get data from a node and append it to a map

  ### Collect examples

      iex> use Eml
      iex> import Eml.Query

      iex> node = html do
      ...>   head do
      ...>     meta charset: "UTF-8"
      ...>   end
      ...>   body do
      ...>     div class: "person" do
      ...>       div [class: "person-name"], "mike"
      ...>       div [class: "person-age"], 23
      ...>     end
      ...>     div class: "person" do
      ...>       div [class: "person-name"], "john"
      ...>       div [class: "person-age"], 42
      ...>     end
      ...>   end
      ...> end

      iex> Eml.collect(node, fn n, acc ->
      ...>   acc
      ...>   |> append(n, content, in: :names, where: attrs.class == "person-name")
      ...>   |> append(n, content, in: :ages, where: attrs.class == "person-age")
      ...> end)
      %{ages: [23, 42], names: ["mike", "john"]}

      iex> collect_person = fn person_node ->
      ...>   Eml.collect(person_node, fn n, acc ->
      ...>     acc
      ...>     |> put(n, content, in: :name, where: attrs.class == "person-name")
      ...>     |> put(n, content, in: :age, where: attrs.class == "person-age")
      ...>   end)
      ...> end

      iex> Eml.collect(node, fn n, acc ->
      ...>   append(acc, n, content, in: :persons, with: collect_person, where: tag == :div and attrs.class == "person")
      ...> end)
      %{persons: [%{age: 23, name: "mike"}, %{age: 42, name: "john"}]}

  ## Chaining queries with `pipe`

 `Eml.Query` also provide the `pipe/3` macro that makes chains of queries more
  readable. The first collect example could be rewritten with the `pipe` macro
  like this:

      iex> Eml.collect(node, fn n, acc ->
      ...>   pipe acc, inject: n do
      ...>     append content, in: :names, where: attrs.class == "person-name"
      ...>     append content, in: :ages, where: attrs.class == "person-age"
      ...>   end
      ...> end)
      %{ages: [23, 42], names: ["mike", "john"]}
  """

  @doc """
  Puts new data into a node

      iex> node = div(42)
      #div<42>

      iex> put node, "Hello World", in: content, where: content == 42
      #div<"Hello World">

      iex> put node, "article", in: attrs.class, where: content == 42
      #div<%{class: "article"} 42>
  """
  defmacro put(node, expr, opts) do
    build_transform(node, prepare_where(opts), fetch!(opts, :in), expr)
  end

  @doc """
  Updates data in a node

      iex> node = div do
      ...>   span 21
      ...>   span 101
      ...> end
      #div<[#span<21>, #span<101>]>

      iex> Eml.transform node, fn n ->
      ...>   update n, content, with: &(&1 * 2), where: tag == :span
      ...> end
      #div<[#span<42>, #span<202>]>
  """
  defmacro update(node, var, opts) do
    validate_var(var)
    expr = Macro.prewalk(var, &handle_attrs/1)
    expr = quote do: unquote(fetch!(opts, :with)).(unquote(expr))
    build_transform(node, prepare_where(opts), var, expr)
  end

  @doc """
  Removes a node in a tree

      iex> node = div do
      ...>   span [class: "remove-me"], 21
      ...>   span 101
      ...> end
      #div<[#span<%{class: "remove-me"} 21>, #span<101>]>

      iex> Eml.transform node, fn n ->
      ...>   drop n, where: attrs.class == "remove-me"
      ...> end
      #div<[#span<101>]>
  """
  defmacro drop(node, opts) do
    quote do
      unquote(inject_vars(node))
      if unquote(prepare_where(opts)), do: nil, else: var!(node)
    end
  end

  @doc """
  Inserts content into an element node

      iex> node = div do
      ...>   span 42
      ...> end
      #div<[#span<42>]>

      iex> Eml.transform(node, fn n ->
      ...>   insert n, 21, where: is_integer(content)
      ...> end
      #div<[#span<[21, 42]>]>
  """
  defmacro insert(node, expr, opts) do
    build_add(node, expr, opts, :insert)
  end

  @doc """
  Appends content into an element node

      iex> node = div do
      ...>   span 42
      ...> end
      #div<[#span<42>]>

      iex> Eml.transform(node, fn n ->
      ...>   append n, 21, where: is_integer(content)
      ...> end
      #div<[#span<[42, 21]>]>
  """
  defmacro append(node, expr, opts) do
    build_add(node, expr, opts, :append)
  end

  @doc """
  Collects data from a node and puts it in a map

  Optionally accepts a `:with` function that allows processing matched
  data before it's being stored in the map.

      iex> node = ul do
      ...>   li "Hello World"
      ...>   li 42
      ...> end
      #ul<[#li<"Hello World">, #li<42>]>

      iex> Eml.collect(node, fn n, acc ->
      ...>   pipe acc, inject: n do
      ...>     put content, in: :number, where: is_integer(content)
      ...>     put content, in: :text, with: &String.upcase/1, where: is_binary(content)
      ...>   end
      ...> end)
      %{number: 42, text: "HELLO WORLD"}
  """
  defmacro put(acc, node, var, opts) do
    build_collect(acc, node, var, opts, :put)
  end

  @doc """
  Collects data from a node and inserts at a given key in a map

  See `Eml.Query.put/4` for more info.

      iex> node = ul do
      ...>   li "Hello World"
      ...>   li 42
      ...> end
      #ul<[#li<"Hello World">, #li<42>]>

      iex> Eml.collect(node, fn n, acc ->
      ...>   pipe acc, inject: n do
      ...>     insert content, in: :list, where: is_integer(content)
      ...>     insert content, in: :list, where: is_binary(content)
      ...>   end
      ...> end)
      %{list: [42, "Hello World"]}
  """
  defmacro insert(acc, node, var, opts) do
    build_collect(acc, node, var, opts, :insert)
  end

  @doc """
  Collects data from a node and appends at a given key in a map

  See `Eml.Query.put/4` for more info.

      iex> node = ul do
      ...>   li "Hello World"
      ...>   li 42
      ...> end
      #ul<[#li<"Hello World">, #li<42>]>

      iex> Eml.collect(node, fn n, acc ->
      ...>   pipe acc, inject: n do
      ...>     append content, in: :list, where: is_integer(content)
      ...>     append content, in: :list, where: is_binary(content)
      ...>   end
      ...> end)
      %{list: ["Hello World", 42]}
  """
  defmacro append(acc, node, var, opts) do
    build_collect(acc, node, var, opts, :append)
  end

  @doc """
  Allows convenient chaing of queries

  See `Eml.Query.put/4` for an example.
  """
  defmacro pipe(x, opts \\ [], do: block) do
    { :__block__, _, calls } = block
    if arg = Keyword.get(opts, :inject) do
      calls = insert_arg(calls, arg)
    end
    pipeline = build_pipeline(x, calls)
    quote do
      unquote(pipeline)
    end
  end

  @doc """
  Returns true if the node matches the `where` expression

      iex> node = div [class: "match-me"], 101
      #div<%{class: "match-me"} 101>

      iex> match_node? node, where: attrs.class == "match-me"
      true
  """
  defmacro match_node?(node, opts) do
    quote do
      unquote(inject_vars(node))
      unquote(prepare_where(opts))
    end
  end

  defp build_transform(node, where, var, expr) do
    key = get_key(var)
    quote do
      unquote(inject_vars(node))
      if unquote(where) do
        Eml.Query.Helper.do_transform(var!(node), unquote(key), unquote(expr))
      else
        var!(node)
      end
    end
  end

  defp build_add(node, expr, opts, op) do
    quote do
      unquote(inject_vars(node))
      if unquote(prepare_where(opts)) do
        Eml.Query.Helper.do_add(var!(node), unquote(expr), unquote(op))
      else
        var!(node)
      end
    end
  end

  defp build_collect(acc, node, var, opts, op) do
    validate_var(var)
    key = fetch!(opts, :in)
    expr = Macro.prewalk(var, &handle_attrs/1)
    if fun = Keyword.get(opts, :with) do
      expr = quote do: unquote(fun).(unquote(expr))
    end
    quote do
      acc = unquote(acc)
      unquote(inject_vars(node))
      if unquote(prepare_where(opts)) do
        Eml.Query.Helper.do_collect(unquote(op), acc, unquote(key), unquote(expr))
      else
        acc
      end
    end
  end

  defp inject_vars(node) do
    quote do
      var!(node) = unquote(node)
      { var!(tag), var!(attrs), var!(content), var!(type) } =
        case var!(node) do
          %Eml.Element{tag: tag, attrs: attrs, content: content, type: type} ->
            { tag, attrs, content, type }
          _ ->
            { nil, %{}, nil, nil }
        end
      _ = var!(node); _ = var!(tag); _ = var!(attrs)
      _ = var!(content); _ = var!(type)
    end
  end

  defp get_key({ key, _, _ }) when key in ~w(node tag attrs content type)a do
    key
  end
  defp get_key({ { :., _, [{ :attrs, _, _ }, key] }, _, _ }) do
    { :attrs, key }
  end
  defp get_key(expr) do
    raise Eml.QueryError,
    message: "only `node`, `tag`, `attrs`, `attrs.{field}, `content` and `type` are valid, got: #{Macro.to_string(expr)}"
  end

  defp validate_var(expr) do
    get_key(expr)
    :ok
  end

  defp fetch!(keywords, key) do
    case Keyword.get(keywords, key, :__undefined) do
      :__undefined ->
        raise Eml.QueryError, message: "Missing `#{inspect key}` option"
      value ->
        value
    end
  end

  defp prepare_where(opts) do
    Macro.prewalk(fetch!(opts, :where), &handle_attrs/1)
  end

  defp build_pipeline(expr, calls) do
    Enum.reduce(calls, expr, fn call, acc ->
      Macro.pipe(acc, call, 0)
    end)
  end

  defp handle_attrs({ { :., _, [{ :attrs, _, _ }, key] }, meta, _ }) do
    line = Keyword.get(meta, :line, 0)
    quote line: line do
      Map.get(var!(attrs), unquote(key))
    end
  end
  defp handle_attrs(expr) do
    expr
  end

  defp insert_arg(calls, arg) do
    Enum.map(calls, fn
      { name, meta, args } when is_atom(name) and (is_list(args) or is_atom(args)) ->
        args = if is_atom(args), do: [], else: args
        { name, meta, [arg | args] }
      _ ->
        raise Eml.QueryError, message: "invalid pipeline"
    end)
  end
end
