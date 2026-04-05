defmodule PhoenixFilamentAI.Components.MarkdownTest do
  use ExUnit.Case, async: true

  alias PhoenixFilamentAI.Components.Markdown

  describe "render_complete/1" do
    test "renders basic markdown to HTML" do
      assert {:ok, html} = Markdown.render_complete("Hello **world**")
      assert html =~ "<strong>world</strong>"
    end

    test "renders headings" do
      assert {:ok, html} = Markdown.render_complete("# Title")
      assert html =~ "<h1>"
      assert html =~ "Title"
    end

    test "renders code blocks with syntax highlighting" do
      markdown = """
      ```elixir
      def hello, do: :world
      ```
      """

      assert {:ok, html} = Markdown.render_complete(markdown)
      # MDEx with html_inline formatter applies inline styles for syntax highlighting
      assert html =~ "def"
      assert html =~ "hello"
    end

    test "renders inline code" do
      assert {:ok, html} = Markdown.render_complete("Use `mix test` to run")
      assert html =~ "<code>"
      assert html =~ "mix test"
    end

    test "renders links" do
      assert {:ok, html} = Markdown.render_complete("[Elixir](https://elixir-lang.org)")
      assert html =~ "<a"
      assert html =~ "https://elixir-lang.org"
    end

    test "renders lists" do
      markdown = """
      - item 1
      - item 2
      - item 3
      """

      assert {:ok, html} = Markdown.render_complete(markdown)
      assert html =~ "<ul>"
      assert html =~ "<li>"
    end

    test "renders tables" do
      markdown = """
      | Col A | Col B |
      |-------|-------|
      | 1     | 2     |
      """

      assert {:ok, html} = Markdown.render_complete(markdown)
      assert html =~ "<table>"
    end

    test "renders strikethrough" do
      assert {:ok, html} = Markdown.render_complete("~~deleted~~")
      assert html =~ "<del>"
    end

    test "sanitizes script tags" do
      assert {:ok, html} = Markdown.render_complete("<script>alert('xss')</script>")
      refute html =~ "<script>"
    end

    test "handles nil input" do
      assert {:ok, ""} = Markdown.render_complete(nil)
    end

    test "handles empty string" do
      assert {:ok, html} = Markdown.render_complete("")
      assert html == ""
    end
  end

  describe "render_complete!/1" do
    test "returns HTML string directly" do
      html = Markdown.render_complete!("**bold**")
      assert html =~ "<strong>bold</strong>"
    end

    test "handles nil input" do
      assert "" == Markdown.render_complete!(nil)
    end
  end

  describe "render_streaming/1" do
    test "renders complete markdown normally" do
      assert {:ok, html} = Markdown.render_streaming("Hello **world**")
      assert html =~ "<strong>world</strong>"
    end

    test "handles unclosed bold markers gracefully" do
      assert {:ok, html} = Markdown.render_streaming("Hello **world")
      assert is_binary(html)
      assert html =~ "world"
    end

    test "handles partial code blocks gracefully" do
      assert {:ok, html} = Markdown.render_streaming("```elixir\ndef hello")
      assert is_binary(html)
      assert html =~ "hello"
    end

    test "handles nil input" do
      assert {:ok, ""} = Markdown.render_streaming(nil)
    end

    test "handles empty string" do
      assert {:ok, html} = Markdown.render_streaming("")
      assert html == ""
    end
  end

  describe "render_streaming!/1" do
    test "returns HTML string directly" do
      html = Markdown.render_streaming!("Hello **world**")
      assert html =~ "<strong>world</strong>"
    end

    test "handles nil input" do
      assert "" == Markdown.render_streaming!(nil)
    end
  end
end
