defmodule PhoenixFilamentAI.Components.Markdown do
  @moduledoc """
  Markdown rendering pipeline using MDEx.

  Provides two rendering modes:

  - `render_complete/1` — for finalized messages. Uses MDEx with sanitization
    and syntax highlighting via MDEx's built-in Lumis formatter.
  - `render_streaming/1` — for in-progress streaming. Best-effort rendering
    that handles incomplete markdown gracefully.
  """

  @doc """
  Renders a complete markdown string to sanitized HTML.

  Uses MDEx with:
  - Syntax highlighting via the `html_inline` formatter (onedark theme)
  - HTML sanitization enabled to prevent XSS

  Returns `{:ok, html}` or `{:error, reason}`.
  """
  @spec render_complete(String.t()) :: {:ok, String.t()} | {:error, term()}
  def render_complete(markdown) when is_binary(markdown) do
    MDEx.to_html(markdown, render_options())
  end

  def render_complete(_), do: {:ok, ""}

  @doc """
  Same as `render_complete/1` but raises on error.
  """
  @spec render_complete!(String.t()) :: String.t()
  def render_complete!(markdown) when is_binary(markdown) do
    MDEx.to_html!(markdown, render_options())
  end

  def render_complete!(_), do: ""

  @doc """
  Renders a streaming (potentially incomplete) markdown string to HTML.

  Best-effort rendering that gracefully handles:
  - Unclosed bold/italic markers
  - Partial code blocks
  - Incomplete lists

  Falls back to returning the raw text wrapped in a `<p>` tag if parsing fails.
  """
  @spec render_streaming(String.t()) :: {:ok, String.t()}
  def render_streaming(markdown) when is_binary(markdown) do
    case render_complete(markdown) do
      {:ok, html} ->
        {:ok, html}

      {:error, _} ->
        {:ok, "<p>#{escape_html(markdown)}</p>\n"}
    end
  end

  def render_streaming(_), do: {:ok, ""}

  @doc """
  Same as `render_streaming/1` but always returns a string.
  """
  @spec render_streaming!(String.t()) :: String.t()
  def render_streaming!(markdown) when is_binary(markdown) do
    {:ok, html} = render_streaming(markdown)
    html
  end

  def render_streaming!(_), do: ""

  defp render_options do
    [
      extension: [
        strikethrough: true,
        table: true,
        autolink: true,
        tasklist: true
      ],
      syntax_highlight: [
        formatter: {:html_inline, theme: "onedark"}
      ],
      sanitize: []
    ]
  end

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
