defmodule PhoenixFilamentAI.Components.TypingIndicatorTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias PhoenixFilamentAI.Components.TypingIndicator

  test "renders typing indicator with dots and text" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <TypingIndicator.typing_indicator />
      """)

    assert html =~ "pfa-typing-indicator"
    assert html =~ "pfa-typing-dot"
    assert html =~ "pfa-typing-text"
    assert html =~ "typing..."
  end

  test "renders exactly three dots" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <TypingIndicator.typing_indicator />
      """)

    dot_count =
      html
      |> String.split("pfa-typing-dot")
      |> length()
      |> Kernel.-(1)

    assert dot_count == 3
  end
end
