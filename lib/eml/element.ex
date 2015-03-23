defmodule Eml.Element do
  @moduledoc """
  `Eml.Element` defines the struct that represents an element in Eml.

  In practice, you will mostly use the element macro's instead of
  directly creating `Eml.Element` structs, but the functions in this
  module can be valuable when querying, manipulating or transforming
  `eml`.
  """
  alias __MODULE__, as: El

  defstruct tag: :div, attrs: %{}, content: nil, template: nil, type: :primitive

  @type attr_name     :: atom
  @type attr_value    :: Eml.t
  @type attrs         :: %{ attr_name => attr_value }
  @type template_fn   :: ((Dict.t) -> { :safe, String.t } | Macro.t)
  @type element_type  :: :primitive | :fragment | :component

  @type t :: %El{tag: atom, content: Eml.t, attrs: attrs, template: template_fn, type: element_type}

  @doc """
  Assign a template function to an element

  Setting the element type is purely informative and has no effect on
  compilation.
  """
  @spec put_template(t, template_fn, element_type) :: t
  def put_template(%El{} = el, fun, type \\ :fragment) do
    %El{el| template: fun, type: type}
  end

  @doc """
  Removes a template function from an element
  """
  @spec remove_template(t) :: t
  def remove_template(%El{} = el) do
    %El{el| template: nil, type: :primitive}
  end

  @doc """
  Calls the template function of an element with its attributes and
  content as argument.

  Raises an `Eml.CompileError` when no template function is present.

  ### Example

      iex> use Eml
      nil
      iex> use Eml.HTML
      nil
      iex> defmodule ElTest do
      ...>
      ...>   fragment my_list do
      ...>     ul class: @class do
      ...>       quote do
      ...>         for item <- @__CONTENT__ do
      ...>           li do
      ...>           end
      ...>         end
      ...>       end
      ...>     end
      ...>   end
      ...>
      ...> end
      {:module, ElTest, ...}
      iex> import ElTest
      nil
      iex> el = my_list class: "some-class" do
      ...>   span 1
      ...>   span 2
      ...> end
      #my_list<%{class: "some-class"} [#span<[1]>, #span<[2]>]>
      iex> Eml.Element.apply_template(el)
      [{:safe, "<ul class='some-class'><li><span>* </span><span>1</span><span> *</span></li><li><span>* </span><span>2</span><span> *</span></li></ul>"}]
  """
  @spec apply_template(t) :: { :safe, String.t } | Macro.t
  def apply_template(%El{attrs: attrs, content: content, template: fun}) when is_function(fun) do
    assigns = Map.put(attrs, :__CONTENT__, content)
    fun.(assigns)
  end
  def apply_template(badarg) do
    raise Eml.CompileError, type: :bad_template_element, data: badarg
  end
end

# Enumerable protocol implementation

defimpl Enumerable, for: Eml.Element do
  def count(_el),           do: { :error, __MODULE__ }
  def member?(_el, _),      do: { :error, __MODULE__ }

  def reduce(el, acc, fun) do
    case reduce_content([el], acc, fun) do
      { :cont, acc }    -> { :done, acc }
      { :suspend, acc } -> { :suspended, acc }
      { :halt, acc }    -> { :halted, acc }
    end
  end

  defp reduce_content(_, { :halt, acc }, _fun) do
    { :halt, acc }
  end
  defp reduce_content(content, { :suspend, acc }, fun) do
    { :suspend, acc, &reduce_content(content, &1, fun) }
  end
  defp reduce_content([%Eml.Element{content: content} = el | rest], { :cont, acc }, fun) do
    reduce_content(rest, reduce_content(content, fun.(el, acc), fun), fun)
  end
  defp reduce_content([node | rest], { :cont, acc }, fun) do
    reduce_content(rest, fun.(node, acc), fun)
  end
  defp reduce_content(nil, acc, _fun) do
    acc
  end
  defp reduce_content([], acc, _fun) do
    acc
  end
  defp reduce_content(node, { :cont, acc }, fun) do
    fun.(node, acc)
  end
end

# Inspect protocol implementation

defimpl Inspect, for: Eml.Element do
  import Inspect.Algebra

  def inspect(%Eml.Element{tag: tag, attrs: attrs, content: content}, opts) do
    opts = if is_list(opts), do: Keyword.put(opts, :hide_content_type, true), else: opts
    tag   = Atom.to_string(tag)
    attrs = if attrs == %{}, do: "", else: to_doc(attrs, opts)
    content  = if content in [nil, "", []], do: "", else: to_doc(content, opts)
    fields = case { attrs, content } do
               { "", "" } -> ""
               { "", _ }  -> content
               { _, "" }  -> attrs
               { _, _ }   -> glue(attrs, " ", content)
             end
    concat ["#", tag, "<", fields, ">"]
  end
end
