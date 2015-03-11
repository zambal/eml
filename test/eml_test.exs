defmodule CustomElement do
  use Eml
  use Eml.HTML.Elements

  element my_element do
    div class: :class do
      h1 :title
      quote do
        for el <- @__CONTENT__, do: el
      end
    end
  end

end

defmodule EmlTest do
  use ExUnit.Case
  use Eml
  use Eml.HTML.Elements

  alias Eml.Element, as: M

  defp doc() do
    %M{tag: :html, content: [
     %M{tag: :head, attrs: %{class: "test"}, content: [
       %M{tag: :title, attrs: %{class: "title"}, content: ["Eml is HTML for developers"]}
     ]},
     %M{tag: :body, attrs: %{class: ["test", "main"]}, content: [
       %M{tag: :h1, attrs: %{class: "title"}, content: ["Eml is HTML for developers"]},
       %M{tag: :article, attrs: %{class: "content", "data-custom": "some custom attribute"},
          content: ["Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam suscipit non neque pharetra dignissim."]},
       %M{tag: :div, attrs: %{id: "main-side-bar", class: ["content", "side-bar"]}, content: [
         %M{tag: :span, attrs: %{class: "test"}, content: ["Some notes..."]}
       ]}
     ]}
   ]}
  end

  test "Element macro" do
    doc = html do
      head class: "test" do
        title [class: "title"], "Eml is HTML for developers"
      end
      body class: ["test", "main"] do
        h1 [class: "title"], "Eml is HTML for developers"
        article [class: "content", "data-custom": "some custom attribute"],
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam suscipit non neque pharetra dignissim."
        div id: "main-side-bar", class: ["content", "side-bar"] do
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
    assert e == Enum.filter(doc(), &Eml.Element.has?(&1, tag: :h1))

    e = [
      head class: "test" do
        title [class: "title"], "Eml is HTML for developers"
      end,
      body class: ["test", "main"] do
        h1 [class: "title"], "Eml is HTML for developers"
        article [class: "content", "data-custom": "some custom attribute"],
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam suscipit non neque pharetra dignissim."
        div id: "main-side-bar", class: ["content", "side-bar"] do
          span([class: "test"], "Some notes...")
        end
      end,
      span([class: "test"], "Some notes...")
    ]
    assert e == Enum.filter(doc(), &Eml.Element.has?(&1, class: "test"))
  end

  test "Render => Parse => Compare" do
    # Parsing always return results in a list
    expected = [doc()]
    { :safe, rendered } = Eml.render(doc())
    assert expected == Eml.parse(rendered)
  end

  test "Types" do
    assert :element     == Eml.type div(42)
    assert :element     == Eml.type Eml.Element.new()
    assert :string      == Eml.type "some text"
    assert :string      == Eml.type Eml.unpackr div(42)
    assert :string      == Eml.type Eml.unpack Eml.encode([1,2,"z"])
    assert :safe_string == Eml.type { :safe, "<div>some text &amp; markup</div>" }
    assert :safe_string == Eml.type Eml.render(Eml.encode(:a))
    assert :safe_string == Eml.type Eml.encode(:name)
                                  |> Eml.compile()
                                  |> Eml.render(name: "Vincent")
    assert :quoted      == Eml.type Eml.compile(Eml.encode(:name))
    assert :quoted      == Eml.type Eml.compile([div([], 1), div([], 2), div([], quote do 2 + @a end), "..."])
  end

  test "Eml.Encoder protocol and encode" do
    assert []                  == Eml.encode [nil, "", []]
    assert ["truefalse"]       == Eml.encode [true, false]
    assert ["12345678"]        == Eml.encode Enum.to_list(1..8)
    assert ["Hello world"]     == Eml.encode ["H", ["el", "lo", [" "]], ["wor", ["ld"]]]
    assert ["Happy new 2015!"] == Eml.encode ["Happy new ", 2, 0, 1, 5, "!"]
    assert_raise Protocol.UndefinedError, fn -> Eml.encode({}) end
  end

  test "Unpack" do
    e = div 42
    assert "42" == Eml.unpack e
    assert "42" == Eml.unpack ["42"]
    assert "42" == Eml.unpack "42"
    assert "42" == Eml.unpack Eml.Element.new(:div, [], 42)

    e = [div(1), div(2)]
    assert e == Eml.unpack e
  end

  test "Single unpackr" do
    single = html do
      body do
        div 42
      end
    end
    assert "42" == Eml.unpackr(single)
  end

  test "Multi unpackr" do
    multi = html do
      body do
        div [ span(1), span(2) ]
        div span(3)
      end
    end
    assert [["1", "2"], "3"] == Eml.unpackr(multi)
  end

  test "Funpackr" do
    multi = html do
      body do
        div [span(1), span(2)]
        div span(3)
      end
    end
    assert ["1", "2", "3"] == Eml.funpackr(multi)
  end

  test "Add content" do
    input = body(id: "test")
    to_add = div("Hello world!")
    expected = body([id: "test"], to_add)

    assert expected == Transform.add(input, to_add, id: "test")
  end

  test "Select by class1" do
    expected = [
      title([class: "title"], "Eml is HTML for developers"),
      h1([class: "title"], "Eml is HTML for developers")
    ]
    result = Query.select(doc(), class: "title")

    # The order of the returned content is unspecified,
    # so we need to compare the nodes.

    assert Enum.all?(result, fn node -> node in expected end)
  end

  test "Select by class 2" do
    expected = [
      head([class: "test"], title([class: "title"], "Eml is HTML for developers")),
      body class: ["test", "main"] do
        h1 [class: "title"], "Eml is HTML for developers"
        article [class: "content", "data-custom": "some custom attribute"],
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam suscipit non neque pharetra dignissim."
        div id: "main-side-bar", class: ["content", "side-bar"] do
          span [class: "test"], "Some notes..."
        end
      end,
      span([class: "test"], "Some notes...")
    ]
    result = Query.select(doc(), class: "test")

    assert Enum.all?(result, fn node -> node in expected end)
  end

  test "Select by id" do
    expected = [div id: "main-side-bar", class: ["content", "side-bar"] do
      span [class: "test"], "Some notes..."
    end]
    result = Query.select(doc(), id: "main-side-bar")

    assert expected == result
  end

  test "Select by id and class 1" do
    expected = [div id: "main-side-bar", class: ["content", "side-bar"] do
      span [class: "test"], "Some notes..."
    end]

    result = Query.select(doc(), id: "main-side-bar", class: "content")

    # If both an id and a class are specified,
    # only return the element that satisfies both.

    assert expected == result
  end

  test "Select by id and class 2" do
    expected = []

    result = Query.select(doc(), id: "main-side-bar", class: "test")

    assert expected == result
  end

  test "Remove by class 1" do
    expected = html do
      head [class: "test"] do
        title [class: "title"], "Eml is HTML for developers"
      end
      body class: ["test", "main"] do
        h1 [class: "title"], "Eml is HTML for developers"
      end
    end
    result = Transform.remove(doc(), class: "content")

    assert expected == result
  end

  test "Remove by class 2" do
    expected = html []
    result   = Transform.remove(doc(), class: "test")

    assert expected == result
  end

  test "Remove by id" do
    expected = html do
      head [class: "test"], do: title([class: "title"], "Eml is HTML for developers")
      body class: ["test", "main"] do
        h1 [class: "title"], "Eml is HTML for developers"
        article [class: "content", "data-custom": "some custom attribute"],
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam suscipit non neque pharetra dignissim."
      end
    end
    result = Transform.remove(doc(), id: "main-side-bar")

    assert expected == result
  end

  test "Remove by id and class" do
    expected = html do
      head [class: "test"], do: title([class: "title"], "Eml is HTML for developers")
      body class: ["test", "main"] do
        h1 [class: "title"], "Eml is HTML for developers"
        article [class: "content", "data-custom": "some custom attribute"],
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam suscipit non neque pharetra dignissim."
      end
    end
    result = Transform.remove(doc(), id: "main-side-bar", class: "content")

    assert expected == result
  end

  test "Member?" do
    assert Query.member?(doc(), id: "main-side-bar")
  end

  test "Assigns" do
    assign = { :quoted, quote context: Eml.Encoder.Atom, do: @an_assign }
    assert [assign]               == Eml.encode(:an_assign)
    assert [assign, "and", assign] == Eml.encode([:an_assign, "and", :an_assign])
  end

  test "Compiling 1" do
    e = div id: (quote do: @myid <> "-collection") do
      div :fruit1
      div :fruit2
    end
    quoted = Eml.compile(e)
    expected = { :safe, "<div id='fruit-collection'><div>lemon</div><div>orange</div></div>" }

    assert :quoted == Eml.type quoted
    assert expected == Eml.render quoted, myid: "fruit", fruit1: "lemon", fruit2: "orange"
  end

  test "Templates" do
    e = for _ <- 1..4 do
      div [], :fruit
    end
    quoted = Eml.compile(e)
    expected = { :safe, "<div>lemon</div><div>lemon</div><div>lemon</div><div>lemon</div>" }

    assert :quoted == Eml.type quoted
    assert expected == Eml.render(quoted, fruit: "lemon")
  end

  test "Custom elements" do
    import CustomElement

    el = my_element class: "some-class", title: "My Title" do
      p 1
      p 2
      p 3
    end

    expected = { :safe, "<div class='some-class'><h1>My Title</h1><p>1</p><p>2</p><p>3</p></div>" }

    assert Eml.render(el) == expected
  end

  test "Quoted content in eml" do
    fruit  = section :fruit
    qfruit = Eml.compile(fruit)
    aside  = aside qfruit
    qaside = Eml.compile(aside)

    assert :quoted == Eml.type qaside

    expected = aside do
      section "lemon"
    end

    assert Eml.render(expected) == Eml.render(qaside, fruit: "lemon")
  end

  test "Quoted attribute rendering" do
    e = div id: :id_assign,
            class: [:class1, "class2", :class3],
            _custom1: (quote do: @custom + 1),
            _custom2: (quote do: @custom + 2)

    expected = { :safe, "<div data-custom1='2' data-custom2='3' class='class1 class2 class3' id='assigned'></div>" }
    assert expected == Eml.render(e, id_assign: "assigned",
                                     class1: "class1",
                                     class3: "class3",
                                     custom: 1)

    quoted = Eml.compile(e)
    assert :quoted == Eml.type quoted
    assert expected == Eml.render(quoted, id_assign: "assigned",
                                          class1: "class1",
                                          class3: "class3",
                                          custom: 1)
  end

  test "Default content escaping" do
    expected = { :safe, "<div>Tom &amp; Jerry</div>" }
    assert expected == Eml.render div("Tom & Jerry")

    expected = { :safe, "<div>Tom &gt; Jerry</div>" }
    assert expected == Eml.render div("Tom > Jerry")

    expected = { :safe, "<div>Tom &lt; Jerry</div>" }
    assert expected == Eml.render div("Tom < Jerry")
  end

  test "Default attributes escaping" do
    expected = { :safe, "<div data-custom='Tom &amp; Jerry'></div>" }
    assert expected == Eml.render div(_custom: "Tom & Jerry")

    expected = { :safe, "<div data-custom='Tom &gt; Jerry'></div>" }
    assert expected == Eml.render div(_custom: "Tom > Jerry")

    expected = { :safe, "<div data-custom='Tom &lt; Jerry'></div>" }
    assert expected == Eml.render div(_custom: "Tom < Jerry")
  end

  test "Attribute quotes escaping" do
    expected = { :safe, "<div data-custom='hello &quot;world&quot;'></div>" }
    assert expected == Eml.render div(_custom: "hello \"world\"")

    expected = { :safe, "<div data-custom='hello &#39;world&#39;'></div>" }
    assert expected == Eml.render div(_custom: "hello 'world'")

    expected = { :safe, "<div data-custom=\"hello &quot;world&quot;\"></div>" }
    assert expected == Eml.render div(_custom: "hello \"world\""), [], quotes: :double

    expected = { :safe, "<div data-custom=\"hello &#39;world&#39;\"></div>" }
    assert expected == Eml.render div(_custom: "hello 'world'"), [], quotes: :double
  end

  test "Content entity parsing" do
    html = "<p>Tom &amp; Jerry</p>"
    assert [p("Tom & Jerry")] == Eml.parse(html)

    html = "<p>Tom &gt; Jerry</p>"
    assert [p("Tom > Jerry")] == Eml.parse(html)

    html = "<p>Tom &lt; Jerry</p>"
    assert [p("Tom < Jerry")] == Eml.parse(html)
  end

  test "Attributes entity parsing" do
    html = "<p data-custom='Tom &amp; Jerry'></p>"
    assert [p("data-custom": "Tom & Jerry")] == Eml.parse(html)

    html = "<p data-custom='Tom &gt; Jerry'></p>"
    assert [p("data-custom": "Tom > Jerry")] == Eml.parse(html)

    html = "<p data-custom='Tom &lt; Jerry'></p>"
    assert [p("data-custom": "Tom < Jerry")] == Eml.parse(html)

    html = "<p data-custom='Tom &#39; Jerry'></p>"
    assert [p("data-custom": "Tom ' Jerry")] == Eml.parse(html)

    html = "<p data-custom=\"Tom &quot; Jerry\"></p>"
    assert [p("data-custom": "Tom \" Jerry")] == Eml.parse(html)
  end

  test "Prerender" do
    e = div do
      span "hallo "
      span "world"
    end
    expected = {:safe, "<div><span>HALLO </span><span>WORLD</span></div>"}

    assert expected == Eml.render(e, [], prerender: &(if is_binary(&1), do: String.upcase(&1), else: &1))
  end

  test "Postrender" do
    e = div do
      span "hallo "
      span "world"
    end
    expected = {:safe, "<DIV><SPAN>HALLO </SPAN><SPAN>WORLD</SPAN></DIV>"}

    assert expected == Eml.render(e, [], postrender: fn chunks ->
      for c <- chunks do
        if is_binary(c), do: String.upcase(c), else: c
      end
    end)
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
