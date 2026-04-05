defmodule PhoenixFilamentAI.Components.TypingIndicator do
  @moduledoc """
  A function component that renders an animated typing indicator.

  Shown during streaming to indicate the AI is generating a response.
  """

  use Phoenix.Component

  @doc """
  Renders the typing indicator with animated dots.

  ## Examples

      <TypingIndicator.typing_indicator />
  """
  def typing_indicator(assigns) do
    ~H"""
    <div class="pfa-typing-indicator">
      <span class="pfa-typing-dot"></span>
      <span class="pfa-typing-dot"></span>
      <span class="pfa-typing-dot"></span>
      <span class="pfa-typing-text">typing...</span>
    </div>
    """
  end
end
