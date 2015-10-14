defmodule Eml.CompileError do
  defexception message: "compile error"
end

defmodule Eml.ParseError do
  defexception message: "parse error"
end

defmodule Eml.QueryError do
  defexception message: "query error"
end
