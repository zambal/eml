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

  test "Native reader 1" do
    assert []                  == eml do: [nil, "", []]
    assert ["truefalse"]       == eml do: [true, false]
    assert ["12345678"]        == eml do: Enum.to_list(1..8)
    assert ["Hello world"]     == eml do: ["H", ["el", "lo", [" "]], ["wor", ["ld"]]]
    assert ["Happy new 2014!"] == eml do: ["Happy new ", 2, 0, 1, 4, "!"]
  end

  test "Native reader 2" do
    assert ["1234"]                          == Eml.read([1,2,3,4], Eml.Readers.Native)
    assert { :error, "Unreadable data: {}" } == Eml.read({}, Eml.Readers.Native)
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
    { :ok, t } = Eml.write(e, pretty: false)

    assert :template == Eml.type(t)
    assert false == Template.bound?(t)
    assert [myid: 1, fruit: 2] == Template.unbound(t)

    t = Template.bind(t, :myid, "double-fruit")
    assert [fruit: 2] == Template.unbound(t)

    t = Template.bind(t, fruit: ["orange", "lemon"])
    assert Template.bound?(t)

    assert "<div id='double-fruit'><div>orange</div><div>lemon</div></div>" ==
      Eml.write!(t)
  end

  test "Templates 2" do
    e = eml do
      [div(:fruit),
       div(:fruit),
       div(:fruit),
       div(:fruit)]
    end
    { :ok, t } = Eml.write(e, pretty: false)

    assert :template == Eml.type(t)
    assert false == Template.bound?(t)
    assert [fruit: 4] == Template.unbound(t)


    t = Template.bind(t, fruit: ["orange", "lemon"])
    assert [fruit: 2] == Template.unbound(t)

    assert "<div>orange</div><div>lemon</div><div>blackberry</div><div>strawberry</div>" ==
      Eml.write!(t, bindings: [fruit: ["blackberry", "strawberry"]])
  end

  test "write => read => compare" do
    html      = Eml.write! doc()
    read_back = Eml.read! html

    assert doc() == read_back
  end


end
