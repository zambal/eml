defmodule EmlTest do
  use ExUnit.Case
  use Eml.Language.HTML
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
    assert [doc()] == doc() |> Eml.render() |> Eml.parse()
  end

  test "Types" do
    assert :element   == Eml.type div(42)
    assert :element   == Eml.type Eml.Element.new()
    assert :binary    == Eml.type "strings are binaries"
    assert :binary    == Eml.type Eml.unpackr div(42)
    assert :binary    == Eml.type Eml.unpack Eml.to_content([1,2,"z"])
    assert :binary    == Eml.type Eml.render(Eml.to_content(:a), [], render_params: true)
    assert :binary    == Eml.type Eml.to_content(:name)
                                  |> Eml.compile()
                                  |> Eml.render(name: "Vincent")
    assert :template  == Eml.type Eml.compile(Eml.to_content(:name))
    assert :template  == Eml.type Eml.compile([div([], 1), div([], 2), div([], :param), "..."])
    assert :parameter == Eml.type %Eml.Parameter{}
  end

  test "Eml.Data protocol and to_content" do
    assert []                  == Eml.to_content [nil, "", []]
    assert ["truefalse"]       == Eml.to_content [true, false]
    assert ["12345678"]        == Eml.to_content Enum.to_list(1..8)
    assert ["Hello world"]     == Eml.to_content ["H", ["el", "lo", [" "]], ["wor", ["ld"]]]
    assert ["Happy new 2015!"] == Eml.to_content ["Happy new ", 2, 0, 1, 5, "!"]
    assert_raise Protocol.UndefinedError, fn -> Eml.to_content({}) end
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

    assert expected == Eml.add(input, to_add, id: "test")
  end

  test "Select by class1" do
    expected = [
      title([class: "title"], "Eml is HTML for developers"),
      h1([class: "title"], "Eml is HTML for developers")
    ]
    result = Eml.select(doc(), class: "title")

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
    result = Eml.select(doc(), class: "test")

    assert Enum.all?(result, fn node -> node in expected end)
  end

  test "Select by id" do
    expected = [div id: "main-side-bar", class: ["content", "side-bar"] do
      span [class: "test"], "Some notes..."
    end]
    result = Eml.select(doc(), id: "main-side-bar")

    assert expected == result
  end

  test "Select by id and class 1" do
    expected = [div id: "main-side-bar", class: ["content", "side-bar"] do
      span [class: "test"], "Some notes..."
    end]

    result = Eml.select(doc(), id: "main-side-bar", class: "content")

    # If both an id and a class are specified,
    # only return the element that satisfies both.

    assert expected == result
  end

  test "Select by id and class 2" do
    expected = []

    result = Eml.select(doc(), id: "main-side-bar", class: "test")

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
    result = Eml.remove(doc(), class: "content")

    assert expected == result
  end

  test "Remove by class 2" do
    expected = html []
    result   = Eml.remove(doc(), class: "test")

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
    result = Eml.remove(doc(), id: "main-side-bar")

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
    result = Eml.remove(doc(), id: "main-side-bar", class: "content")

    assert expected == result
  end

  test "Member?" do
    assert Eml.member?(doc(), id: "main-side-bar")
  end

  test "Parameters" do
    param = %Eml.Parameter{id: :a_parameter}
    assert [param]               == Eml.to_content(:a_parameter)
    assert [param, "and", param] == Eml.to_content([:a_parameter, "and", :a_parameter])
  end

  test "Templates 1" do
    e = div id: :myid do
      div :fruit1
      div :fruit2
    end
    t = Eml.compile(e)

    assert :template == Eml.type t
    assert false == Eml.Template.bound?(t)
    assert [:myid, :fruit1, :fruit2] == Eml.Template.unbound(t)

    t = Eml.Template.bind(t, :myid, "double-fruit")
    assert [:fruit1, :fruit2] == Eml.Template.unbound(t)

    t = Eml.Template.bind(t, fruit1: "orange", fruit2: "lemon")
    assert Eml.Template.bound?(t)
  end

  test "Templates 2" do
    e = for _ <- 1..4 do
      div [], :fruit
    end
    t = Eml.compile(e)

    assert :template == Eml.type t
    assert false == Eml.Template.bound?(t)
    assert [:fruit] == Eml.Template.unbound(t)

    t = Eml.Template.bind(t, fruit: "lemon")
    assert [] == Eml.Template.unbound(t)

    assert "<div>lemon</div><div>lemon</div><div>lemon</div><div>lemon</div>" ==
      Eml.render(t)
  end

  test "Templates in eml" do
    fruit  = section :fruit
    tfruit = Eml.compile(fruit)
    aside  = aside tfruit
    taside = Eml.compile(aside)

    assert :template == Eml.type taside

    expected = aside do
      section "lemon"
    end

    assert Eml.render(expected) == Eml.render(taside, fruit: "lemon")
  end

  test "Parse parameters from html" do
    html       = "<div><span>#param{name}</span><span>#param{age}</span></div"
    name_param = %Eml.Parameter{id: :name}
    age_param  = %Eml.Parameter{id: :age}
    eml        = Eml.parse(html)

    assert [name_param, age_param] == Eml.unpackr eml
  end

  test "Parameterized attribute rendering" do
    e = div id: :id_param,
            class: [:class1, "class2", :class3],
            _custom1: :custom,
            _custom2: :custom

    expected1 = "<div data-custom1='#param{custom}' data-custom2='#param{custom}' class='#param{class1} class2 #param{class3}' id='#param{id_param}'></div>"
    assert expected1 == Eml.render(e, [], render_params: true)

    expected2 = "<div data-custom1='1' data-custom2='1' class='class1 class2 class3' id='parameterized'></div>"
    assert expected2 == Eml.render(e, id_param: "parameterized",
                                       class1: "class1",
                                       class3: "class3",
                                       custom: 1)

    t = Eml.compile(e, class3: "class3", custom: 1)
    assert :template == Eml.type t
    assert Enum.sort([:id_param, :class1]) == Enum.sort(Eml.Template.unbound(t))
    assert expected2 == Eml.render(t, id_param: "parameterized", class1: "class1")
  end
end
