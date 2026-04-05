defmodule PhoenixFilamentAI.Components.ToolCallCard do
  @moduledoc """
  A stateful LiveComponent that renders a collapsible tool call card.

  Collapsed state shows the tool name and a status badge.
  Expanded state additionally shows the input and output as pretty-printed JSON.

  Toggle via `phx-click`.
  """

  use Phoenix.LiveComponent

  @impl true
  def mount(socket) do
    {:ok, assign(socket, :expanded, false)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("toggle", _params, socket) do
    {:noreply, assign(socket, :expanded, !socket.assigns.expanded)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pfa-tool-call-card">
      <button
        type="button"
        class="pfa-tool-call-header"
        phx-click="toggle"
        phx-target={@myself}
      >
        <span class="pfa-tool-call-name">{tool_name(@message)}</span>
        <span class={["pfa-tool-call-status", status_class(@message)]}>{status_text(@message)}</span>
      </button>

      <div :if={@expanded} class="pfa-tool-call-body">
        <div :if={Map.get(@message, :input)} class="pfa-tool-call-section">
          <div class="pfa-tool-call-section-label">Input</div>
          <pre class="pfa-tool-call-json">{format_json(Map.get(@message, :input))}</pre>
        </div>

        <div :if={Map.get(@message, :output)} class="pfa-tool-call-section">
          <div class="pfa-tool-call-section-label">Output</div>
          <pre class="pfa-tool-call-json">{format_json(Map.get(@message, :output))}</pre>
        </div>
      </div>
    </div>
    """
  end

  defp tool_name(message) do
    Map.get(message, :tool_name, "Tool Call")
  end

  defp status_text(message) do
    case Map.get(message, :status) do
      :running -> "Running"
      :completed -> "Done"
      :failed -> "Failed"
      _ -> "Pending"
    end
  end

  defp status_class(message) do
    case Map.get(message, :status) do
      :running -> "pfa-status-running"
      :completed -> "pfa-status-completed"
      :failed -> "pfa-status-failed"
      _ -> "pfa-status-pending"
    end
  end

  defp format_json(nil), do: ""

  defp format_json(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      {:error, _} -> data
    end
  end

  defp format_json(data) when is_map(data) or is_list(data) do
    Jason.encode!(data, pretty: true)
  end

  defp format_json(data), do: inspect(data)
end
