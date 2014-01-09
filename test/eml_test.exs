defmodule EmlTest do
  use ExUnit.Case
  use Eml
  use Eml.Markup.Record

  defp doc() do
    [m(tag: :html, content: [
      m(tag: :head, class: "test", content: [
        m(tag: :title, class: "title", content: ["Eml is Html for developers"])
      ]),
      m(tag: :body, class: ["test", "main"], content: [
        m(tag: :h1, class: "title", content: ["Eml is Html for developers"]),
        m(tag: :article, class: "content", attrs: [_custom: "some custom attribute"],
           content: ["Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam suscipit non neque pharetra dignissim."]),
        m(tag: :div, id: "main-side-bar", class: ["content", "side-bar"], content: [
          m(tag: :span, class: "test", content: ["Some notes..."])
        ])
      ])
    ])]
  end

  test "Markup macro" do
    doc = eml do
      html do
        head [class: "test"] do
          title [class: "title"], "Eml is Html for developers"
        end
        body [class: ["test", "main"]] do
          h1 [class: "title"], "Eml is Html for developers"
          article [class: "content", _custom: "some custom attribute"],
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam suscipit non neque pharetra dignissim."
          div [id: "main-side-bar", class: ["content", "side-bar"]] do
            span [class: "test"], "Some notes..."
          end
        end
      end
    end

    assert doc() == doc
  end

  test "Write => Read => Compare" do
    assert doc() == doc() |> Eml.write!() |> Eml.read!()
  end

  test "Types" do
    assert :content   == Eml.type eml(do: div 42)
    assert :content   == Eml.type eml(do: [1,2,"z"])
    assert :content   == Eml.type eml(do: "")
    assert :content   == Eml.type eml(do: [])
    assert :content   == Eml.type eml(do: nil)
    assert :markup    == Eml.type Eml.Markup.new()
    assert :markup    == Eml.type unpack eml(do: div 42)
    assert :binary    == Eml.type "strings are binaries"
    assert :binary    == Eml.type Eml.unpackr eml(do: div 42)
    assert :binary    == Eml.type unpack eml(do: [1,2,"z"])
    assert :binary    == Eml.type Eml.write! eml(do: :name)
    assert :binary    == Eml.type eml(do: :name)
                                  |> Eml.compile()
                                  |> Eml.write!(bindings: [name: "Vincent"])
    assert :template  == Eml.type eml(do: [:name, :age])
                                  |> Eml.compile()
                                  |> Eml.write!(bindings: [age: 36])
    assert :template  == Eml.type eml(do: [:name, :age])
                                  |> Eml.write!(bindings: [age: 36])
    assert :template  == Eml.type Eml.compile eml(do: :name)
    assert :template  == Eml.type Eml.compile eml(do: [div(1), div(2), div(:param), "..."])
    assert :parameter == Eml.type Eml.Parameter.new(:param)
    assert :parameter == Eml.type unpack eml(do: :param)
  end

  test "Native" do
    assert []                  == eml do: [nil, "", []]
    assert ["truefalse"]       == eml do: [true, false]
    assert ["12345678"]        == eml do: Enum.to_list(1..8)
    assert ["Hello world"]     == eml do: ["H", ["el", "lo", [" "]], ["wor", ["ld"]]]
    assert ["Happy new 2014!"] == eml do: ["Happy new ", 2, 0, 1, 4, "!"]
  end

  test "Native read" do
    assert ["1234"]                          == Eml.read([1,2,3,4], Eml.Language.Native)
    assert { :error, "Unreadable data: {}" } == Eml.read({}, Eml.Language.Native)
  end

  test "Unpack" do
    e = eml do: div 42
    assert "42" == unpack unpack e
    assert "42" == unpack ["42"]
    assert "42" == unpack "42"
    assert "42" == unpack Eml.Markup.new(content: 42)

    e = eml do: [div(1), div(2)]
    assert e == unpack e
  end

  test "Single unpackr" do
    single = eml do: 42 |> div |> body |> html
    assert "42" == Eml.unpackr(single)
  end

  test "Multi unpackr" do
    multi = eml do
      html do
        body do
          div [ span(1), span(2) ]
          div [ span(3) ]
        end
      end
    end
    assert [["1", "2"], "3"] == Eml.unpackr(multi)
  end

  test "Funpackr" do
    multi = eml do
      html do
        body do
          div [ span(1), span(2) ]
          div [ span(3) ]
        end
      end
    end
    assert ["1", "2", "3"] == Eml.funpackr(multi)
  end

  test "Add markup" do
    input = eml do: body([id: "test"], "")
    to_add = eml do: div("Hello world!")
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
    # so we need to compare the elements.

    assert Enum.all?(result, fn element -> element in expected end)
  end

  test "Select by class 2" do
    expected = eml do
      [
       head([class: "test"], title([class: "title"], "Eml is Html for developers")),
       body class: ["test", "main"] do
         h1 [class: "title"], "Eml is Html for developers"
         article [class: "content", _custom: "some custom attribute"],
         "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam suscipit non neque pharetra dignissim."
         div [id: "main-side-bar", class: ["content", "side-bar"]] do
           span [class: "test"], "Some notes..."
         end
       end,
       span([class: "test"], "Some notes...")
      ]
    end
    result = Eml.select(doc(), class: "test")

    assert Enum.all?(result, fn element -> element in expected end)
  end

  test "Select by id" do
    expected = eml do
      div [id: "main-side-bar", class: ["content", "side-bar"]] do
        span([class: "test"], "Some notes...")
      end
    end
    result = Eml.select(doc(), id: "main-side-bar")

    assert expected == result
  end

  test "Select by id and class 1" do
    expected = eml do
      div [id: "main-side-bar", class: ["content", "side-bar"]] do
        span([class: "test"], "Some notes...")
      end
    end

    result = Eml.select(doc(), id: "main-side-bar", class: "content")

    # If both an id and a class are specified,
    # only return the markup that satisfies both.

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
        head [class: "test"], do: title([class: "title"], "Eml is Html for developers")
        body class: ["test", "main"] do
          h1 [class: "title"], "Eml is Html for developers"
        end
      end
    end
    result = Eml.remove(doc(), class: "content")

    assert expected == result
  end

  test "Remove by class 2" do
    expected = eml do: html []
    result   = Eml.remove(doc(), class: "test")

    assert expected == result
  end

  test "Remove by id" do
    expected = eml do
      html do
        head [class: "test"], do: title([class: "title"], "Eml is Html for developers")
        body class: ["test", "main"] do
          h1 [class: "title"], "Eml is Html for developers"
          article [class: "content", _custom: "some custom attribute"],
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
          article [class: "content", _custom: "some custom attribute"],
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
    param = Eml.Parameter.new(:a_parameter)
    assert [param]               == eml do: :a_parameter
    assert [param, "and", param] == eml do: [:a_parameter, "and", :a_parameter]
  end

  test "Templates 1" do
    e = eml do
      div [id: :myid] do
        div :fruit
        div :fruit
      end
    end
    t = Eml.compile(e)

    assert :template == Eml.type t
    assert false == Template.bound?(t)
    assert [myid: 1, fruit: 2] == Template.unbound(t)

    t = Template.bind(t, :myid, "double-fruit")
    assert [fruit: 2] == Template.unbound(t)

    t = Template.bind(t, fruit: ["orange", "lemon"])
    assert Template.bound?(t)

    assert "<div id='double-fruit'>\n  <div>orange</div>\n  <div>lemon</div>\n</div>" ==
      Eml.write!(t, pretty: true)
  end

  test "Templates 2" do
    e = eml do
      [div(:fruit),
       div(:fruit),
       div(:fruit),
       div(:fruit)]
    end
    t = Eml.compile(e)

    assert :template == Eml.type t
    assert false == Template.bound?(t)
    assert [fruit: 4] == Template.unbound(t)


    t = Template.bind(t, fruit: ["orange", "lemon"])
    assert [fruit: 2] == Template.unbound(t)

    assert "<div>orange</div><div>lemon</div><div>blackberry</div><div>strawberry</div>" ==
      Eml.write!(t, bindings: [fruit: ["blackberry", "strawberry"]])
  end

  test "Templates in eml" do
    fruit  = eml do: section(:fruit)
    tfruit = Eml.compile(fruit)
    aside  = eml do: aside tfruit
    taside = Eml.compile(aside)

    assert :template == Eml.type taside

    expected = eml do
      aside [ section "lemon" ]
    end

    assert Eml.write!(expected) == Eml.write!(taside, bindings: [fruit: "lemon"])

  end

  test "Read parameters from html" do
    html       = "<div><span>#param{name}</span><span>#param{age}</span></div"
    name_param = Eml.Parameter.new(:name)
    age_param  = Eml.Parameter.new(:age)
    eml        = Eml.read(html)

    assert [name_param, age_param] == Eml.unpackr eml
  end

  test "Parameterized attribute rendering" do
    e = eml do
      div [id: :id_param,
           class: [:class1, "class2", :class3],
           _custom1: :custom,
           _custom2: :custom], []
    end

    expected1 = "<div id='#param{id_param}' class='#param{class1} class2 #param{class3}'" <>
                " data-custom1='#param{custom}' data-custom2='#param{custom}'/>"
    assert expected1 == Eml.write!(e)

    expected2 = "<div id='parameterized' class='class1 class2 class3' data-custom1='1' data-custom2='2'/>"
    assert expected2 == Eml.write!(e, bindings: [id_param: "parameterized",
                                                 class1: "class1",
                                                 class3: "class3",
                                                 custom: [1, 2]])

    t = Eml.write!(e, bindings: [class3: "class3", custom: 1])
    assert :template == Eml.type t
    assert [id_param: 1, class1: 1, custom: 1] == Template.unbound(t)
    assert expected2 == Eml.write!(t, bindings: [id_param: "parameterized", class1: "class1", custom: 2])
  end
end
