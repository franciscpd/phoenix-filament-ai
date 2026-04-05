defmodule PhoenixFilamentAI.Components.MessageComponent do
  @moduledoc """
  A Phoenix function component that renders a single chat message.

  ## Attributes

  - `:message` (required) — map with `:role` and `:content` (and optionally `:id`,
    `:tool_name`, `:input`, `:output`, `:status`)
  - `:streaming` — boolean, whether the message is currently being streamed (default: `false`)
  - `:on_retry` — event name for retry button, `nil` if no retry (default: `nil`)

  ## Rendering by role

  - `:user` — full-width block, slightly darker bg, markdown rendered
  - `:assistant` — full-width block, light bg, markdown rendered (streaming mode during active stream)
  - `:system` — highlighted banner (amber), smaller text, no markdown
  - `:error` — red banner, error icon, retry button (if on_retry provided)
  - `:tool_call` — delegates to `PhoenixFilamentAI.Components.ToolCallCard`
  """

  use Phoenix.Component

  alias PhoenixFilamentAI.Components.Markdown
  alias PhoenixFilamentAI.Components.ToolCallCard

  attr(:message, :map, required: true)
  attr(:streaming, :boolean, default: false)
  attr(:on_retry, :string, default: nil)

  @doc """
  Renders a single chat message based on its role.
  """
  def message(assigns) do
    ~H"""
    <div class={["pfa-message", role_class(@message.role)]}>
      {render_by_role(assigns)}
    </div>
    """
  end

  defp render_by_role(%{message: %{role: :user}} = assigns) do
    ~H"""
    <div class="pfa-message-content pfa-message-user">
      {render_markdown(@message.content, false)}
    </div>
    """
  end

  defp render_by_role(%{message: %{role: :assistant}} = assigns) do
    ~H"""
    <div class="pfa-message-content pfa-message-assistant">
      {render_markdown(@message.content, @streaming)}
    </div>
    """
  end

  defp render_by_role(%{message: %{role: :system}} = assigns) do
    ~H"""
    <div class="pfa-message-content pfa-message-system">
      <span class="pfa-system-text">{@message.content}</span>
    </div>
    """
  end

  defp render_by_role(%{message: %{role: :error}} = assigns) do
    ~H"""
    <div class="pfa-message-content pfa-message-error">
      <span class="pfa-error-icon">&#9888;</span>
      <span class="pfa-error-text">{@message.content}</span>
      <button :if={@on_retry} class="pfa-retry-btn" phx-click={@on_retry}>
        Retry
      </button>
    </div>
    """
  end

  defp render_by_role(%{message: %{role: :tool_call}} = assigns) do
    ~H"""
    <.live_component module={ToolCallCard} id={tool_call_id(@message)} message={@message} />
    """
  end

  defp render_by_role(assigns) do
    ~H"""
    <div class="pfa-message-content pfa-message-unknown">
      {render_markdown(@message.content, false)}
    </div>
    """
  end

  defp render_markdown(content, true) do
    content
    |> Markdown.render_streaming!()
    |> Phoenix.HTML.raw()
  end

  defp render_markdown(content, false) do
    content
    |> Markdown.render_complete!()
    |> Phoenix.HTML.raw()
  end

  defp role_class(:user), do: "pfa-role-user"
  defp role_class(:assistant), do: "pfa-role-assistant"
  defp role_class(:system), do: "pfa-role-system"
  defp role_class(:error), do: "pfa-role-error"
  defp role_class(:tool_call), do: "pfa-role-tool-call"
  defp role_class(_), do: "pfa-role-unknown"

  defp tool_call_id(%{id: id}) when not is_nil(id), do: "tool-call-#{id}"
  defp tool_call_id(_), do: "tool-call-#{System.unique_integer([:positive])}"
end
