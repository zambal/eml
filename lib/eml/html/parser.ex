defmodule Eml.HTML.Parser do
  @moduledoc false

  # API

  @spec parse(binary, Keyword.t) :: [Eml.t]
  def parse(html, opts \\ []) do
    res = tokenize(html, { :blank, [] }, [], :blank, opts) |> parse_content()
    case res do
      { content, [] } ->
        content
      { content, rest }->
        raise Eml.ParseError, message: "Unparsable content, parsed: #{inspect content}, rest: #{inspect rest}"
    end
  end

  # Tokenize

  # Skip comments
  defp tokenize("<!--" <> rest, buf, acc, state, opts)
  when state != :comment do
    tokenize(rest, buf, acc, :comment, opts)
  end
  defp tokenize("-->" <> rest, buf, acc, :comment, opts) do
    { state, _ } = buf
    tokenize(rest, buf, acc, state, opts)
  end
  defp tokenize(<<_>> <> rest, buf, acc, :comment, opts) do
    tokenize(rest, buf, acc, :comment, opts)
  end

  # Skip doctype
  defp tokenize("<!DOCTYPE" <> rest, buf, acc, :blank, opts) do
    tokenize(rest, buf, acc, :doctype, opts)
  end
  defp tokenize("<!doctype" <> rest, buf, acc, :blank, opts) do
    tokenize(rest, buf, acc, :doctype, opts)
  end
  defp tokenize(">" <> rest, buf, acc, :doctype, opts) do
    tokenize(rest, buf, acc, :blank, opts)
  end
  defp tokenize(<<_>> <> rest, buf, acc, :doctype, opts) do
    tokenize(rest, buf, acc, :doctype, opts)
  end

  # CDATA
  defp tokenize("<![CDATA[" <> rest, buf, acc, state, opts)
  when state in [:content, :blank, :start_close, :end_close, :close] do
    next(rest, buf, "", acc, :cdata, opts)
  end
  defp tokenize("]]>" <> rest, buf, acc, :cdata, opts) do
    next(rest, buf, "", acc, :content, opts)
  end
  defp tokenize(<<char>> <> rest, buf, acc, :cdata, opts) do
    consume(char, rest, buf, acc, :cdata, opts)
  end
  # Makes it possible for elements to treat its contents as if cdata
  defp tokenize(chars, buf, acc, { :cdata, end_tag } = state, opts) do
    end_token = "</" <> end_tag <> ">"
    n = byte_size(end_token)
    case chars do
      <<^end_token::binary-size(n), rest::binary>> ->
        acc = change(buf, acc, :cdata)
        acc = change({ :open, "<" }, acc)
        acc = change({ :slash, "/" }, acc)
        acc = change({ :end_tag, end_tag }, acc)
        tokenize(rest, { :end_close, ">" }, acc, :end_close, opts)
      <<char>> <> rest ->
        consume(char, rest, buf, acc, state, opts)
      "" ->
        :lists.reverse([buf | acc])
    end
  end

  # Attribute quotes
  defp tokenize("'" <> rest, buf, acc, :attr_sep, opts) do
    next(rest, buf, "'", acc, :attr_single_open, opts)
  end
  defp tokenize("\"" <> rest, buf, acc, :attr_sep, opts) do
    next(rest, buf, "\"", acc, :attr_double_open, opts)
  end
  defp tokenize(<<char>> <> rest, buf, acc, :attr_value, opts) when char in [?\", ?\'] do
    case { char, previous_state(acc, [:attr_value]) } do
      t when t in [{ ?\', :attr_single_open }, { ?\", :attr_double_open }] ->
        next(rest, buf, char, acc, :attr_close, opts)
      _else ->
        consume(char, rest, buf, acc, :attr_value, opts)
    end
  end
  defp tokenize(<<char>> <> rest, buf, acc, state, opts)
  when { char, state } in [{ ?\', :attr_single_open }, { ?\", :attr_double_open }] do
    next(rest, buf, char, acc, :attr_close, opts)
  end

  # Attributes values accept any character
  defp tokenize(<<char>> <> rest, buf, acc, state, opts)
  when state in [:attr_single_open, :attr_double_open] do
    next(rest, buf, char, acc, :attr_value, opts)
  end
  defp tokenize(<<char>> <> rest, buf, acc, :attr_value, opts) do
    consume(char, rest, buf, acc, :attr_value, opts)
  end

  # Attribute field/value seperator
  defp tokenize("=" <> rest, buf, acc, :attr_field, opts) do
    next(rest, buf, "=", acc, :attr_sep, opts)
  end

  # Allow boolean attributes, ie. attributes with only a field name
  defp tokenize(<<char>> <> rest, buf, acc, :attr_field, opts)
  when char in [?\>, ?\s, ?\n, ?\r, ?\t] do
    next(<<char, rest::binary>>, buf, "\"", acc, :attr_close, opts)
  end

  # Whitespace handling
  defp tokenize(<<char>> <> rest, buf, acc, state, opts)
  when char in [?\s, ?\n, ?\r, ?\t] do
    case state do
      :start_tag ->
        next(rest, buf, "", acc, :start_tag_close, opts)
      s when s in [:close, :start_close, :end_close] ->
        if char in [?\n, ?\r] do
          next(rest, buf, "", acc, :content, opts)
        else
          next(rest, buf, char, acc, :content, opts)
        end
      :content ->
        consume(char, rest, buf, acc, state, opts)
      _ ->
        tokenize(rest, buf, acc, state, opts)
    end
  end

  # Open tag
  defp tokenize("<" <> rest, buf, acc, state, opts) do
    case state do
      s when s in [:blank, :start_close, :end_close, :close, :content] ->
        next(rest, buf, "<", acc, :open, opts)
      _ ->
        error("<", rest, buf, acc, state)
    end
  end

  # Close tag
  defp tokenize(">" <> rest, buf, acc, state, opts) do
    case state do
      s when s in [:attr_close, :start_tag] ->
        # The html tokenizer doesn't support elements without proper closing.
        # However, it does makes exceptions for tags specified in is_void_element?/1
        # and assume they never have children.
        tag = get_last_tag(acc, buf)
        if is_void_element?(tag) do
          next(rest, buf, ">", acc, :close, opts)
        else
          # check if the content of the element should be interpreted as cdata
          case element_type([buf | acc], List.wrap(opts[:treat_as_cdata])) do
            :content ->
              next(rest, buf, ">", acc, :start_close, opts)
            { :cdata, tag } ->
              acc = change(buf, acc)
              next(rest, { :start_close, ">" }, "", acc, { :cdata, tag }, opts)
          end
        end
      :slash ->
        next(rest, buf, ">", acc, :close, opts)
      :end_tag ->
        next(rest, buf, ">", acc, :end_close, opts)
      _ ->
        def_tokenize(">" <> rest, buf, acc, state, opts)
    end
  end

  # Slash
  defp tokenize("/" <> rest, buf, acc, state, opts)
  when state in [:open, :attr_field, :attr_close, :start_tag, :start_tag_close] do
    next(rest, buf, "/", acc, :slash, opts)
  end

  defp tokenize("", buf, acc, _, _opts) do
    :lists.reverse([buf | acc])
  end

  # Default parsing
  defp tokenize(chars, buf, acc, state, opts), do: def_tokenize(chars, buf, acc, state, opts)

  # Either start or consume content or tag.
  defp def_tokenize(<<char>> <> rest, buf, acc, state, opts) do
    case state do
      s when s in [:start_tag, :end_tag, :attr_field, :content] ->
        consume(char, rest, buf, acc, state, opts)
      s when s in [:blank, :start_close, :end_close, :close] ->
        next(rest, buf, char, acc, :content, opts)
      s when s in [:attr_close, :start_tag_close] ->
        next(rest, buf, char, acc, :attr_field, opts)
      :open ->
        next(rest, buf, char, acc, :start_tag, opts)
      :slash ->
        next(rest, buf, char, acc, :end_tag, opts)
      _ ->
        error(char, rest, buf, acc, state)
    end
  end

  # Stops tokenizing and dumps all info in a tuple
  defp error(char, rest, buf, acc, state) do
    char = if is_integer(char), do: <<char>>, else: char
    state = [state: state,
             char: char,
             buf: buf,
             last_token: List.first(acc),
             next_char: String.first(rest)]
    raise Eml.ParseError, message: "Illegal token, parse state is: #{inspect state}"
  end

  # Consumes character and put it in the buffer
  defp consume(char, rest, { type, buf }, acc, state, opts) do
    char = if is_integer(char), do: <<char>>, else: char
    tokenize(rest, { type, buf <> char }, acc, state, opts)
  end

  # Add the old buffer to the accumulator and start a new buffer
  defp next(rest, old_buf, new_buf, acc, new_state, opts) do
    acc = change(old_buf, acc)
    new_buf = if is_integer(new_buf), do: <<new_buf>>, else: new_buf
    tokenize(rest, { new_state, new_buf }, acc, new_state, opts)
  end

  # Add buffer to the accumulator if its content is not empty.
  defp change({ type, buf }, acc, type_modifier \\ nil) do
    type = if is_nil(type_modifier), do: type, else: type_modifier
    token = { type, buf }
    if empty?(token) do
      acc
    else
      [token | acc]
    end
  end

  # Checks for empty content
  defp empty?({ :blank, _ }), do: true
  defp empty?({ :content, content }) do
    String.strip(content) === ""
  end
  defp empty?(_), do: false

  # Checks if last tokenized tag is a tag that should always close.
  defp get_last_tag(tokens, { type, buf }) do
    get_last_tag([{ type, buf } | tokens])
  end

  defp get_last_tag([{ :start_tag, tag } | _]), do: tag
  defp get_last_tag([_ | ts]), do: get_last_tag(ts)
  defp get_last_tag([]), do: nil

  defp is_void_element?(tag) do
    tag in ["area", "base", "br", "col", "embed", "hr", "img", "input", "keygen", "link", "meta", "param", "source", "track", "wbr"]
  end

  defp previous_state([{ state, _ } | rest], skip_states) do
    if state in skip_states do
      previous_state(rest, skip_states)
    else
      state
    end
  end
  defp previous_state([], _), do: :blank

  # CDATA element helper

  @cdata_elements ["script", "style"]

  defp element_type(acc, extra_cdata_elements) do
    cdata_elements = @cdata_elements ++ extra_cdata_elements
    case get_last_tag(acc) do
      nil ->
        :content
      tag ->
        if tag in cdata_elements do
          { :cdata, tag }
        else
          :content
        end
    end
  end

  # Parse the genrated tokens

  defp parse_content(tokens) do
    parse_content(tokens, [])
  end

  defp parse_content([{ type, token } | ts], acc) do
    case preparse(type, token) do
      :skip ->
        parse_content(ts, acc)
      { :tag, tag } ->
        { element, tokens } = parse_element(ts, [tag: tag, attrs: [], content: []])
        parse_content(tokens, [element | acc])
      { :content, content } ->
        parse_content(ts, [content | acc])
      { :cdata, content } ->
        # tag cdata in order to skip whitespace trimming
        parse_content(ts, [{ :cdata, content } | acc])
      :end_el ->
        { :lists.reverse(acc), ts }
    end
  end
  defp parse_content([], acc) do
    { :lists.reverse(acc), [] }
  end

  defp parse_element([{ type, token } | ts], acc) do
    case preparse(type, token) do
      :skip ->
        parse_element(ts, acc)
      { :attr_field, field } ->
        attrs = [{ field, "" } | acc[:attrs]]
        parse_element(ts, Keyword.put(acc, :attrs, attrs))
      { :attr_value, value } ->
        [{ field, current } | rest] = acc[:attrs]
        attrs = if is_binary(current) && is_binary(value) do
                  [{ field, current <> value } | rest]
                else
                  [{ field, List.wrap(current) ++ [value] } | rest]
                end
        parse_element(ts, Keyword.put(acc, :attrs, attrs))
      :start_content ->
        { content, tokens } = parse_content(ts, [])
        { make_element(Keyword.put(acc, :content, content)), tokens }
      :end_el ->
        { make_element(acc), ts }
    end
  end
  defp parse_element([], acc) do
    { make_element(acc), [] }
  end

  defp make_element(acc) do
    attrs = acc[:attrs]
    %Eml.Element{tag: acc[:tag], attrs: Enum.into(attrs, %{}), content: finalize_content(acc[:content], acc[:tag])}
  end

  defp preparse(:blank, _),            do: :skip
  defp preparse(:open, _),             do: :skip
  defp preparse(:slash, _),            do: :skip
  defp preparse(:attr_single_open, _), do: :skip
  defp preparse(:attr_double_open, _), do: :skip
  defp preparse(:attr_close, _),       do: :skip
  defp preparse(:attr_sep, _),         do: :skip
  defp preparse(:end_tag, _),          do: :skip
  defp preparse(:start_tag_close, _),  do: :skip

  defp preparse(:attr_field, token) do
    { :attr_field, String.to_atom(token) }
  end

  defp preparse(:attr_value, token), do: { :attr_value, token }
  defp preparse(:start_tag, token), do: { :tag, String.to_atom(token) }
  defp preparse(:start_close, _), do: :start_content
  defp preparse(:content, token), do: { :content, token }
  defp preparse(:end_close, _), do: :end_el
  defp preparse(:close, _), do: :end_el

  defp preparse(:cdata, token), do: { :cdata, token }

  defp finalize_content(content, tag)
  when tag in [:textarea, :pre] do
    case content do
      [content] when is_binary(content) ->
        content
      [] ->
        nil
      content ->
        content
    end
  end
  defp finalize_content(content, _) do
    case content do
      [content] when is_binary(content) ->
        trim_whitespace(content, :only)
      [] ->
        nil
      [first | rest] ->
        first = trim_whitespace(first, :first)
        [first | trim_whitespace_loop(rest, [])]
    end
  end

  defp trim_whitespace_loop([last], acc) do
    last = trim_whitespace(last, :last)
    :lists.reverse([last | acc])
  end
  defp trim_whitespace_loop([h | t], acc) do
    trim_whitespace_loop(t, [trim_whitespace(h, :other) | acc])
  end
  defp trim_whitespace_loop([], acc) do
    acc
  end

  defp trim_whitespace(content, position) do
    trim_whitespace(content, "", false, position)
  end

  defp trim_whitespace(<<char>> <> rest, acc, in_whitespace?, pos) do
    if char in [?\s, ?\n, ?\r, ?\t] do
      if in_whitespace? do
        trim_whitespace(rest, acc, true, pos)
      else
        trim_whitespace(rest, acc <> " ", true, pos)
      end
    else
      trim_whitespace(rest, acc <> <<char>>, false, pos)
    end
  end
  defp trim_whitespace("", acc, _, pos) do
    case pos do
      :first -> String.lstrip(acc)
      :last  -> String.rstrip(acc)
      :only  -> String.strip(acc)
      :other -> acc
    end
  end
  defp trim_whitespace({ :cdata, noop }, _, _, _), do: noop
  defp trim_whitespace(noop, _, _, _), do: noop
end
