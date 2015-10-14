defmodule EmlTest.Fragment do
  use Eml

  fragment my_fragment do
    div class: @class do
      h1 @title
      @__CONTENT__
    end
  end
end

defmodule EmlTest.Template do
  use Eml

  import EmlTest.Fragment, warn: false

  template my_template,
  title: &String.upcase/1,
  paragraphs: &(for par <- &1, do: p par) do
    my_fragment class: @class, title: @title do
      h3 "Paragraphs"
      @paragraphs
    end
  end
end

defmodule EmlTest do
  use ExUnit.Case
  use Eml

  alias Eml.Element, as: M

  defp doc() do
    %M{tag: :html, content: [
      %M{tag: :head, attrs: %{class: "test"}, content: [
        %M{tag: :title, attrs: %{class: "title"}, content: "Eml is HTML for developers"}
      ]},
      %M{tag: :body, attrs: %{class: "test main"}, content: [
        %M{tag: :h1, attrs: %{class: "title"}, content: "Eml is HTML for developers"},
        %M{tag: :article, attrs: %{class: "content", "data-custom": "some custom attribute"},
           content: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam suscipit non neque pharetra dignissim."},
        %M{tag: :div, attrs: %{id: "main-side-bar", class: "content side-bar"},
           content: [%M{tag: :span, attrs: %{class: "test"}, content: "Some notes..."}]}
      ]}
    ]}
  end

  test "Element macro" do
    doc = html do
      head class: "test" do
        title [class: "title"], "Eml is HTML for developers"
      end
      body class: "test main" do
        h1 [class: "title"], "Eml is HTML for developers"
        article [class: "content", "data-custom": "some custom attribute"],
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam suscipit non neque pharetra dignissim."
        div id: "main-side-bar", class: "content side-bar" do
          span [class: "test"], "Some notes..."
        end
      end
    end

    assert doc() == doc
  end

  test "Element macro as match pattern" do
    span(%{id: id}, _) = %M{tag: :span, attrs: %{id: "test"}, content: []}
    assert "test" == id
  end

  test "Enumerate content" do
    assert true == Enum.member?(doc(), "Some notes...")

    e = [h1([class: "title"], "Eml is HTML for developers")]
    assert e == Enum.filter(doc(), fn
      %M{tag: :h1} -> true
      _ -> false
    end)
  end

  test "Compile => Parse => Compare" do
    # Parsing always return results in a list
    expected = [doc()]
    compiled = Eml.compile(doc())
    assert expected == Eml.parse(compiled)
  end

  test "Eml.Encoder protocol and encode" do
    assert "true" == Eml.Encoder.encode true
    assert_raise Protocol.UndefinedError, fn -> Eml.Encoder.encode({}) end
  end

  test "Unpack" do
    e = div 42
    assert 42   == Eml.unpack e
    assert "42" == Eml.unpack ["42"]
    assert "42" == Eml.unpack "42"
    assert "42" == Eml.unpack %M{tag: :div, attrs: %{}, content: ["42"]}

    e = [div(1), div(2)]
    assert [1, 2] == Eml.unpack e
  end

  test "Multi unpack" do
    multi = html do
      body do
        div [ span(1), span(2) ]
        div span(3)
      end
    end
    assert [[1, 2], 3] == Eml.unpack(multi)
  end

  test "Compiling" do
    e = quote do
      div id: @myid do
        div @fruit1
        div @fruit2
      end
    end

    { chunks, _ } = Eml.Compiler.precompile(fragment: true, do: e)
    |> Code.eval_quoted(assigns: [myid: "fruit", fruit1: "lemon", fruit2: "orange"])
    compiled = Eml.Compiler.concat(chunks, [])

    expected = { :safe, "<div id='fruit'><div>lemon</div><div>orange</div></div>" }

    assert expected == compiled
  end

  test "Templates" do
    e = quote do
      for _ <- 1..4 do
        div [], @fruit
      end
    end
    { chunks, _ } = Eml.Compiler.precompile(fragment: true, do: e)
    |> Code.eval_quoted(assigns: [fruit: "lemon"])
    compiled = Eml.Compiler.concat(chunks, [])

    expected = { :safe, "<div>lemon</div><div>lemon</div><div>lemon</div><div>lemon</div>" }

    assert expected == compiled
  end

  test "fragment elements" do
    import EmlTest.Template

    el = my_template class: "some'class", title: "My&Title", paragraphs: [1, 2, 3]

    expected = "<div class='some&#39;class'><h1>MY&amp;TITLE</h1><h3>Paragraphs</h3><p>1</p><p>2</p><p>3</p></div>"

    assert Eml.compile(el) == expected
  end

  test "Quoted content in eml" do
    fruit  = quote do: section @fruit
    qfruit = Eml.Compiler.precompile(fragment: true, do: fruit)
    aside  = aside qfruit
    qaside = Eml.Compiler.compile(aside)

    expected = aside do
      section "lemon"
    end

    { chunks, _ } = Code.eval_quoted(qaside, assigns: [fruit: "lemon"])
    { :safe, string } = Eml.Compiler.concat(chunks, [])

    assert Eml.compile(expected) == string
  end

  test "Assigns and attribute compiling" do
    e = quote do
      div id: @id_assign,
      class: [@class1, " class2 ", @class3],
      _custom: @custom
    end

    { chunks, _ } = Eml.Compiler.precompile(fragment: true, do: e)
    |> Code.eval_quoted(assigns: [id_assign: "assigned",
                                  class1: "class1",
                                  class3: "class3",
                                  custom: 1])
    compiled = Eml.Compiler.concat(chunks, [])

    expected = { :safe, "<div data-custom='1' class='class1 class2 class3' id='assigned'></div>" }

    assert expected == compiled
  end

  test "Content escaping" do
    expected = "Tom &amp; Jerry"
    assert expected == Eml.escape "Tom & Jerry"

    expected = "Tom &gt; Jerry"
    assert expected == Eml.escape "Tom > Jerry"

    expected = "Tom &lt; Jerry"
    assert expected == Eml.escape "Tom < Jerry"

    expected = "hello &quot;world&quot;"
    assert expected == Eml.escape "hello \"world\""

    expected = "hello &#39;world&#39;"
    assert expected == Eml.escape "hello 'world'"

    expected = div span("Tom &amp; Jerry")
    assert expected == Eml.escape div span("Tom & Jerry")

    expected = "<div><span>Tom &amp; Jerry</span></div>"
    assert expected == Eml.compile div span("Tom & Jerry")

    expected = "<div><span>Tom & Jerry</span></div>"
    assert expected == Eml.compile div span({ :safe, "Tom & Jerry" })
  end

  test "Content unescaping" do
    expected = "Tom & Jerry"
    assert expected == Eml.unescape "Tom &amp; Jerry"

    expected = "Tom > Jerry"
    assert expected == Eml.unescape "Tom &gt; Jerry"

    expected = "Tom < Jerry"
    assert expected == Eml.unescape "Tom &lt; Jerry"

    expected = "hello \"world\""
    assert expected == Eml.unescape "hello &quot;world&quot;"

    expected = "hello 'world'"
    assert expected == Eml.unescape "hello &#39;world&#39;"

    expected = div span("Tom & Jerry")
    assert expected == Eml.unescape div span("Tom &amp; Jerry")
  end

  test "Precompile transform" do
    e = div do
      span "hallo "
      span "world"
    end
    expected = "<div><span>HALLO </span><span>WORLD</span></div>"

    assert expected == Eml.compile(e, transform: &(if is_binary(&1), do: String.upcase(&1), else: &1))
  end

  test "Element casing" do
    name = :some_long_element_name

    assert name == Eml.Element.Generator.do_casing(name, :snake)
    assert :"SOME_LONG_ELEMENT_NAME" == Eml.Element.Generator.do_casing(name, :snake_upcase)
    assert :"SomeLongElementName"    == Eml.Element.Generator.do_casing(name, :pascal)
    assert :"someLongElementName"    == Eml.Element.Generator.do_casing(name, :camel)
    assert :"some-long-element-name" == Eml.Element.Generator.do_casing(name, :lisp)
    assert :"SOME-LONG-ELEMENT-NAME" == Eml.Element.Generator.do_casing(name, :lisp_upcase)
  end
end
