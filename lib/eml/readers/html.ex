defmodule Eml.Readers.Html do
  @behaviour Eml.Reader

  alias Eml.Markup

  # API

  @spec read(binary, atom) :: Eml.element | Eml.error
  def read(html, BitString) do
    res = case html |> String.codepoints() |> parse({ :blank, [] }, [], :blank) do
            { :error, state } ->
              { :error, state }
            tokens ->
              compile(tokens)
          end
    case res do
      { :error, state } ->
        { :error, state }
      { markup, [] } ->
        markup
      { markup, rest }->
        { :error, [compiled: markup, rest: rest] }
    end
  end

  # Html parsing

  # Skip doctype
  defp parse(["<", "!" | cs], buf, acc, :blank) do
    parse(cs, buf, acc, :doctype)
  end
  defp parse([">" | cs], buf, acc, :doctype) do
    parse(cs, buf, acc, :blank)
  end
  defp parse([_ | cs], buf, acc, :doctype) do
    parse(cs, buf, acc, :doctype)
  end

  # When inside entity, accept any char, except ';'
  defp parse([c | cs], buf, acc, :entity) when c != ";" do
    consume(c, cs, buf, acc, :entity)
  end

  # Allow boolean attributes, ie. attributes with only a field name
  defp parse([c | cs], buf, acc, :attr_field)
  when c in [">", " ", "\n", "\r", "\t"] do
    { state, acc } = change(buf, acc, :attr_sep)
    { state, acc } = change({ state, ["="] }, acc, :attr_open)
    { state, acc } = change({ state, ["\""] }, acc, :attr_value)
    next([c|cs], { state, [""] }, ["\""], acc, :attr_close)
  end

  # Handle newline in content
  defp parse([c1, c2 | cs], buf, acc, state)
  when c1 in ["\n", "\r"] and c2 in [" ", "\t"]
  and state in [:attr_value, :content] do
    next(cs, buf, [c2], acc, :content_newline)
  end

  defp parse([c1, c2 | cs], buf, acc, state)
  when c1 in ["\n", "\r"] and c2 in ["\n", "\r"]
  and state in [:attr_value, :content] do
    next(cs, buf, [], acc, :content_newline)
  end

  defp parse([c | cs], buf, acc, state)
  when c in ["\n", "\r"]
  and state in [:attr_value, :content] do
    next(cs, buf, [" "], acc, :content_newline)
  end

  # Most other whitespace handling
  defp parse([c | cs], buf, acc, state)
  when c in [" ", "\n", "\r", "\t"] do
    case state do
      :start_tag ->
        next(cs, buf, [], acc, :start_tag_close)
      s when s in [:close, :start_close, :end_close] ->
        next(cs, buf, [c], acc, :content)
      s when s in [:attr_value, :content] ->
        consume(c, cs, buf, acc, state)
      :close_entity ->
        state = state_before_entity(acc)
        next(cs, buf, [c], acc, state)
      _ ->
        parse(cs, buf, acc, state)
    end
  end

  # Either start or consume content, tag,
  # or attribute character.
  defp parse([c | cs], buf, acc, state)
  when (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c in ["_", ":"] do
    case state do
      s when s in [:start_tag, :end_tag, :attr_field, :attr_value, :content, :entity] ->
        consume(c, cs, buf, acc, state)
      s when s in [:blank, :start_close, :end_close, :close, :content_newline] ->
        next(cs, buf, [c], acc, :content)
      :open ->
        next(cs, buf, [c], acc, :start_tag)
      :slash ->
        next(cs, buf, [c], acc, :end_tag)
      :start_tag_close ->
        next(cs, buf, [c], acc, :attr_field)
      :attr_open ->
        next(cs, buf, [c], acc, :attr_value)
      :attr_close ->
        next(cs, buf, [c], acc, :attr_field)
      :open_entity ->
        next(cs, buf, [c], acc, :entity)
      :close_entity ->
        state = state_before_entity(acc)
        next(cs, buf, [c], acc, state)
      _ ->
        error(c, cs, buf, acc, state)
    end
  end

  # Open tag
  defp parse(["<" | cs], buf, acc, state) do
    case state do
      s when s in [:blank, :start_close, :end_close, :close, :content, :content_newline] ->
        next(cs, buf, ["<"], acc, :open)
      _ ->
        error("<", cs, buf, acc, state)
    end
  end

  # Close tag
  defp parse([">" | cs], buf, acc, state) do
    case state do
      s when s in [:attr_close, :start_tag] ->
        # The html parser doesn't support arbitrary markup without proper closing.
        # However, it does makes exceptions for tags specified in close_last_tag?/1/2
        # and assume they never have children.
        if close_last_tag?(acc, buf) do
          next(cs, buf, [">"], acc, :close)
        else
          next(cs, buf, [">"], acc, :start_close)
        end
      :slash ->
        next(cs, buf, [">"], acc, :close)
      :end_tag ->
        next(cs, buf, [">"], acc, :end_close)
      _ ->
        error(">", cs, buf, acc, state)
    end
  end

  # Attribute field/value seperator
  defp parse(["=" | cs], buf, acc, state) do
    case state do
      s when s in [:attr_value, :content, :content_newline] ->
        consume("=", cs, buf, acc, state)
      :attr_field ->
        next(cs, buf, ["="], acc, :attr_sep)
      _ ->
        error("=", cs, buf, acc, state)
    end
  end

  # Start entity
  defp parse(["&" | cs], buf, acc, state) do
    case state do
      s when s in [:attr_value, :content, :content_newline] ->
        next(cs, buf, ["&"], acc, :open_entity)
      _ ->
        error("&", cs, buf, acc, state)
    end
  end

  # End entity
  defp parse([";" | cs], buf, acc, :entity) do
    next(cs, buf, [";"], acc, :close_entity)
  end

  # Slash
  defp parse(["/" | cs], buf, acc, state) do
    case state do
      s when s in [:attr_value, :content, :content_newline] ->
        consume("/", cs, buf, acc, state)
      s when s in [:open, :attr_field, :attr_close, :start_tag] ->
        next(cs, buf, ["/"], acc, :slash)
      _ ->
        error("/", cs, buf, acc, state)
    end
  end

  # Attribute quotes
  defp parse([c | cs], buf, acc, state)
  when c in ["\"", "'"] do
    case state do
      s when s in [:content, :content_newline] ->
        consume(c, cs, buf, acc, state)
      :attr_sep ->
        next(cs, buf, [c], acc, :attr_open)
      :attr_value ->
        next(cs, buf, [c], acc, :attr_close)
      :attr_open ->
        { state, acc } = change({ state, [c] }, acc, :attr_value)
        next(cs, { state, [""] }, [c], acc, :attr_close)
      _ ->
        error(c, cs, buf, acc, state)
    end
  end

  # Content
  defp parse([c | cs], buf, acc, state)
  when not c in ["<"] do
    case state do
      s when s in [:start_tag, :end_tag, :attr_field, :attr_value, :content, :entity] ->
        consume(c, cs, buf, acc, state)
      s when s in [:blank, :start_close, :end_close, :close, :content_newline] ->
        next(cs, buf, [c], acc, :content)
      :attr_open ->
        next(cs, buf, [c], acc, :attr_value)
      :open_entity ->
        next(cs, buf, [c], acc, :entity)
      :close_entity ->
        state = state_before_entity(acc)
        next(cs, buf, [c], acc, state)
      _ ->
        error(c, cs, buf, acc, state)
    end
  end

  defp parse([], { type, buf }, acc, _) do
    :lists.reverse([{ type, stringify(buf) } | acc])
  end

  # Stops tokenizing and dumps all info in a tuple
  defp error(char, rest, { type, buf }, acc, state) do
    state = [state: state,
             char: char,
             buf: { type, :lists.reverse(buf) },
             last_token: Enum.first(acc),
             next_char: Enum.first(rest)]
    { :error, state}
  end

  # Consumes character and put it in the buffer
  defp consume(char, rest, { type, buf }, acc, state) do
    parse(rest, { type, [char | buf] }, acc, state)
  end

  # Add the old buffer to the accumulator and start a new buffer
  defp next(rest, old_buf, new_buf, acc, new_state) do
    { state, acc } = change(old_buf, acc, new_state)
    parse(rest, { state, new_buf }, acc, state)
  end

  # Stringify the buffer and add it to the accumulator if not empty content.
  defp change({ type, buf }, acc, new_state) do
    token = { type, stringify(buf) }
    if empty?(token) do
      { new_state, acc }
    else
      { new_state, [token | acc] }
    end
  end

  defp stringify(buf) when is_list(buf) do
    buf |> :lists.reverse() |> iolist_to_binary()
  end

  # Checks for empty content
  defp empty?({ :blank, _ }), do: true
  defp empty?({ :content, token }) do
    :re.replace(token, "\\s", "", [:global, { :return, :binary }]) === ""
  end
  defp empty?(_), do: false

  # Checks if last parsed tag is a tag that should always close.
  # Currently those tags are: br and meta
  defp close_last_tag?(tokens, { type, buf }) do
    close_last_tag?([{ type, stringify(buf) } | tokens])
  end

  defp close_last_tag?([{ :start_tag, tag } | _])
  when tag in ["br", "meta"], do: true
  defp close_last_tag?([{ :start_tag, _ } | _]), do: false
  defp close_last_tag?([_ | ts]), do: close_last_tag?(ts)
  defp close_last_tag?([]), do: false

  defp state_before_entity([{ :open_entity, _ }, { state, _ } | _]), do: state
  defp state_before_entity([{ :open_entity, _ } | _]), do: :blank
  defp state_before_entity([_ | t]), do: state_before_entity(t)
  defp state_before_entity([]), do: :error
  
  # Compile the genrated tokens

  defp compile(tokens) do
    compile(tokens, [attrs: []], :cont)
  end

  defp compile([{ type, token } | ts] = tokens, acc, state) do
    case precompile(type, token) do
      :skip -> compile(ts, acc, state)
      { type, token } when type in [:tag, :content] ->
        if(state == :in_content) do
          { data, rest } = compile(tokens)
          compile(rest, Keyword.update(acc, :content, [data], fn content ->
            [data | content]
          end), state)
        else
          if type == :tag do
            compile(ts, [{ :tag, token } | acc], state)
          else
            { token, ts }
          end
        end
      { :attr_field, field } ->
        attrs = [{ field, nil } | acc[:attrs]]
        compile(ts, Keyword.put(acc, :attrs, attrs), state)
      { :attr_value, value } ->
        [{ field, nil } | rest] = acc[:attrs]
        attrs = [{ field, value } | rest]
        compile(ts, Keyword.put(acc, :attrs, attrs), state)
      :start_content ->
        compile(ts, acc, :in_content)
      :end_el ->
        {id, attrs } = Keyword.pop(acc[:attrs], :id)
        {class, attrs } = Keyword.pop(attrs, :class)
        { Markup.new(tag: acc[:tag],
                     id: id,
                     class: class_value(class),
                     attrs: :lists.reverse(attrs),
                     content: :lists.reverse(Keyword.get(acc, :content, []))),
          ts }
    end

  end

  defp compile([], acc, _ ) do
    {id, attrs } = Keyword.pop(acc[:attrs], :id)
    {class, attrs } = Keyword.pop(attrs, :class)
    { Markup.new(tag: acc[:tag], id: id, class: class, attrs: attrs, content: acc[:content]), [] }
  end

  defp precompile(:blank, _),           do: :skip
  defp precompile(:open, _),            do: :skip
  defp precompile(:slash, _),           do: :skip
  defp precompile(:attr_open, _),       do: :skip
  defp precompile(:attr_close, _),      do: :skip
  defp precompile(:attr_sep, _),        do: :skip
  defp precompile(:end_tag, _),         do: :skip
  defp precompile(:start_tag_close, _), do: :skip
  defp precompile(:open_entity, _),     do: :skip
  defp precompile(:close_entity, _),    do: :skip

  defp precompile(:content_newline, ""), do: :skip
  defp precompile(:content_newline, token) do
    { :content, token }
  end

  defp precompile(:attr_field, token) do
    if String.starts_with?(token, "data-") do
      { :attr_field, String.replace(token, "data-", "_") |> binary_to_atom() }
    else
      { :attr_field, binary_to_atom(token) }
    end
  end

  defp precompile(:attr_value, token), do: {:attr_value, token }
  defp precompile(:start_tag, token), do: {:tag, binary_to_atom(token) }
  defp precompile(:start_close, _), do: :start_content
  defp precompile(:content, token), do: {:content, token }
  defp precompile(:end_close, _), do: :end_el
  defp precompile(:close, _), do: :end_el

  defp precompile(:entity, "amp"), do: {:content, "&" }
  defp precompile(:entity, "lt"), do: {:content, "<" }
  defp precompile(:entity, "gt"), do: {:content, ">" }


  defp class_value(nil), do: nil
  defp class_value(value) do
    case String.split(value, " ") do
      [class] -> class
      classes -> classes
    end
  end
end