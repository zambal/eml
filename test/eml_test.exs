defmodule EmlTest do
  use ExUnit.Case
  use Eml
  alias Eml.Element, as: M

  defp doc() do
    [%M{tag: :html, content: [
      %M{tag: :head, attrs: %{class: "test"}, content: [
        %M{tag: :title, attrs: %{class: "title"}, content: ["Eml is Html for developers"]}
      ]},
      %M{tag: :body, attrs: %{class: ["test", "main"]}, content: [
        %M{tag: :h1, attrs: %{class: "title"}, content: ["Eml is Html for developers"]},
        %M{tag: :article, attrs: %{class: "content", "data-custom": "some custom attribute"},
           content: ["Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam suscipit non neque pharetra dignissim."]},
        %M{tag: :div, attrs: %{id: "main-side-bar", class: ["content", "side-bar"]}, content: [
          %M{tag: :span, attrs: %{class: "test"}, content: ["Some notes..."]}
        ]}
      ]}
    ]}]
  end

  test "Element macro" do
    doc = eml do
      html do
        head class: "test" do
          title [class: "title"], "Eml is Html for developers"
        end
        body class: ["test", "main"] do
          h1 [class: "title"], "Eml is Html for developers"
          article [class: "content", "data-custom": "some custom attribute"],
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam suscipit non neque pharetra dignissim."
          div id: "main-side-bar", class: ["content", "side-bar"] do
            span [class: "test"], "Some notes..."
          end
        end
      end
    end

    assert doc() == doc
  end

  test "Element macro as match pattern" do
    e = eml do
      span(%{id: id}, _) = %M{tag: :span, attrs: %{id: "test"}, content: []}
      id
    end
    assert "test" == unpack(e)
  end

  test "Enumerate content" do
    assert true == Enum.member?(unpack(doc()), "Some notes...")

    e = eml do
      h1 [class: "title"], ["Eml is Html for developers"]
    end
    assert e == Enum.filter(unpack(doc()), &Element.has?(&1, tag: :h1))

    e = eml do
      [
        head class: "test" do
          title [class: "title"], "Eml is Html for developers"
        end,
        body class: ["test", "main"] do
          h1 [class: "title"], "Eml is Html for developers"
          article [class: "content", "data-custom": "some custom attribute"],
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam suscipit non neque pharetra dignissim."
          div id: "main-side-bar", class: ["content", "side-bar"] do
            span [class: "test"], "Some notes..."
          end
        end,
        span([class: "test"], "Some notes...")
      ]
    end
    assert e == Enum.filter(unpack(doc()), &Element.has?(&1, class: "test"))
  end

  test "Render => Parse => Compare" do
    assert doc() == doc() |> Eml.render!() |> Eml.parse!()
  end

  test "Types" do
    assert :content   == Eml.type eml do: div([], 42)
    assert :content   == Eml.type eml do: [1,2,"z"]
    assert :content   == Eml.type eml do: ""
    assert :content   == Eml.type eml do: []
    assert :content   == Eml.type eml do: nil
    assert :element    == Eml.type Eml.Element.new()
    assert :element    == Eml.type unpack(eml do: div([], 42))
    assert :binary    == Eml.type "strings are binaries"
    assert :binary    == Eml.type Eml.unpackr(eml do: div([], 42))
    assert :binary    == Eml.type unpack(eml do: [1,2,"z"])
    assert :binary    == Eml.type Eml.render!((eml do: :name), [], render_params: true)
    assert :binary    == Eml.type (eml do: :name)
                                  |> Eml.compile()
                                  |> Eml.render!(name: "Vincent")
    assert :template  == Eml.type Eml.compile(eml do: :name)
    assert :template  == Eml.type Eml.compile(eml do: [div([], 1), div([], 2), div([], :param), "..."])
    assert :parameter == Eml.type %Eml.Parameter{}
    assert :parameter == Eml.type unpack(eml do: :param)
  end

  test "Native" do
    assert []                  == eml do: [nil, "", []]
    assert ["truefalse"]       == eml do: [true, false]
    assert ["12345678"]        == eml do: Enum.to_list(1..8)
    assert ["Hello world"]     == eml do: ["H", ["el", "lo", [" "]], ["wor", ["ld"]]]
    assert ["Happy new 2015!"] == eml do: ["Happy new ", 2, 0, 1, 5, "!"]
  end

  test "Native parse" do
    assert ["1234"]                          == Eml.parse([1,2,3,4], Eml.Language.Native)
    assert { :error, "Unparsable data: {}" } == Eml.parse({}, Eml.Language.Native)
  end

  test "Unpack" do
    e = eml do: div([], 42)
    assert "42" == unpack unpack e
    assert "42" == unpack ["42"]
    assert "42" == unpack "42"
    assert "42" == unpack Eml.Element.new(:div, [], 42)

    e = eml do: [div([], 1), div([], 2)]
    assert e == unpack e
  end

  test "Single unpackr" do
    single = eml do
      html do
        body do
          div [], 42
        end
      end
    end
    assert "42" == Eml.unpackr(single)
  end

  test "Multi unpackr" do
    multi = eml do
      html do
        body do
          div [], [ span([], 1), span([], 2) ]
          div [], span([], 3)
        end
      end
    end
    assert [["1", "2"], "3"] == Eml.unpackr(multi)
  end

  test "Funpackr" do
    multi = eml do
      html do
        body do
          div [], [span([], 1), span([], 2)]
          div [], span([], 3)
        end
      end
    end
    assert ["1", "2", "3"] == Eml.funpackr(multi)
  end

  test "Add content" do
    input = eml do: body(id: "test")
    to_add = eml do: div([], "Hello world!")
    expected = eml do: body([id: "test"], to_add)

    assert expected == Eml.add(input, to_add, id: "test")
  end

  test "Select by class1" do
    expected = eml do
      [
       title([class: "title"], "Eml is Html for developers"),
       h1([class: "title"], "Eml is Html for developers")
      ]
    end
    result = Eml.select(doc(), class: "title")

    # The order of the returned content is unspecified,
    # so we need to compare the nodes.

    assert Enum.all?(result, fn node -> node in expected end)
  end

  test "Select by class 2" do
    expected = eml do
      [
       head([class: "test"], title([class: "title"], "Eml is Html for developers")),
       body class: ["test", "main"] do
         h1 [class: "title"], "Eml is Html for developers"
         article [class: "content", "data-custom": "some custom attribute"],
         "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam suscipit non neque pharetra dignissim."
         div id: "main-side-bar", class: ["content", "side-bar"] do
           span [class: "test"], "Some notes..."
         end
       end,
       span([class: "test"], "Some notes...")
      ]
    end
    result = Eml.select(doc(), class: "test")

    assert Enum.all?(result, fn node -> node in expected end)
  end

  test "Select by id" do
    expected = eml do
      div id: "main-side-bar", class: ["content", "side-bar"] do
        span [class: "test"], "Some notes..."
      end
    end
    result = Eml.select(doc(), id: "main-side-bar")

    assert expected == result
  end

  test "Select by id and class 1" do
    expected = eml do
      div id: "main-side-bar", class: ["content", "side-bar"] do
        span [class: "test"], "Some notes..."
      end
    end

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
    expected = eml do
      html do
        head [class: "test"] do
          title [class: "title"], "Eml is Html for developers"
        end
        body class: ["test", "main"] do
          h1 [class: "title"], "Eml is Html for developers"
        end
      end
    end
    result = Eml.remove(doc(), class: "content")

    assert expected == result
  end

  test "Remove by class 2" do
    expected = eml do: html([], [])
    result   = Eml.remove(doc(), class: "test")

    assert expected == result
  end

  test "Remove by id" do
    expected = eml do
      html do
        head [class: "test"], do: title([class: "title"], "Eml is Html for developers")
        body class: ["test", "main"] do
          h1 [class: "title"], "Eml is Html for developers"
          article [class: "content", "data-custom": "some custom attribute"],
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam suscipit non neque pharetra dignissim."
        end
      end
    end
    result = Eml.remove(doc(), id: "main-side-bar")

    assert expected == result
  end

  test "Remove by id and class" do
    expected = eml do
      html do
        head [class: "test"], do: title([class: "title"], "Eml is Html for developers")
        body class: ["test", "main"] do
          h1 [class: "title"], "Eml is Html for developers"
          article [class: "content", "data-custom": "some custom attribute"],
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam suscipit non neque pharetra dignissim."
        end
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
    assert [param]               == eml do: :a_parameter
    assert [param, "and", param] == eml do: [:a_parameter, "and", :a_parameter]
  end

  test "Templates 1" do
    e = eml do
      div id: :myid do
        div [], :fruit1
        div [], :fruit2
      end
    end
    t = Eml.compile(e)

    assert :template == Eml.type t
    assert false == Template.bound?(t)
    assert [:myid, :fruit1, :fruit2] == Template.unbound(t)

    t = Template.bind(t, :myid, "double-fruit")
    assert [:fruit1, :fruit2] == Template.unbound(t)

    t = Template.bind(t, fruit1: "orange", fruit2: "lemon")
    assert Template.bound?(t)
  end

  test "Templates 2" do
    e = eml do
      for _ <- 1..4 do
        div [], :fruit
      end
    end
    t = Eml.compile(e)

    assert :template == Eml.type t
    assert false == Template.bound?(t)
    assert [:fruit] == Template.unbound(t)

    t = Template.bind(t, fruit: "lemon")
    assert [] == Template.unbound(t)

    assert "<div>lemon</div><div>lemon</div><div>lemon</div><div>lemon</div>" ==
      Eml.render!(t)
  end

  test "Templates in eml" do
    fruit  = eml do: section([], :fruit)
    tfruit = Eml.compile(fruit)
    aside  = eml do: aside([], tfruit)
    taside = Eml.compile(aside)

    assert :template == Eml.type taside

    expected = eml do
      aside do
        section [], "lemon"
      end
    end

    assert Eml.render!(expected) == Eml.render!(taside, fruit: "lemon")
  end

  test "Parse parameters from html" do
    html       = "<div><span>#param{name}</span><span>#param{age}</span></div"
    name_param = %Eml.Parameter{id: :name}
    age_param  = %Eml.Parameter{id: :age}
    eml        = Eml.parse(html)

    assert [name_param, age_param] == Eml.unpackr eml
  end

  test "Parameterized attribute rendering" do
    e = eml do
      div id: :id_param,
          class: [:class1, "class2", :class3],
          _custom1: :custom,
          _custom2: :custom
    end

    expected1 = "<div data-custom1='#param{custom}' data-custom2='#param{custom}' class='#param{class1} class2 #param{class3}' id='#param{id_param}'></div>"
    assert expected1 == Eml.render!(e, [], render_params: true)

    expected2 = "<div data-custom1='1' data-custom2='1' class='class1 class2 class3' id='parameterized'></div>"
    assert expected2 == Eml.render!(e, id_param: "parameterized",
                                       class1: "class1",
                                       class3: "class3",
                                       custom: 1)

    t = Eml.compile(e, [class3: "class3", custom: 1])
    assert :template == Eml.type t
    assert Enum.sort([:id_param, :class1]) == Enum.sort(Template.unbound(t))
    assert expected2 == Eml.render!(t, id_param: "parameterized", class1: "class1")
  end
end
