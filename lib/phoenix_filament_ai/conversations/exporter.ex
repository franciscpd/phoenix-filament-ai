defmodule PhoenixFilamentAI.Conversations.Exporter do
  @moduledoc """
  Exports conversations to JSON and Markdown formats.

  Accepts a conversation map (as returned by `StoreAdapter.get_conversation_with_stats/2`)
  and serializes it to a portable format for download or archival.
  """

  @doc """
  Serializes a conversation to pretty-printed JSON.

  Includes top-level fields (id, title, user_id, tags, model, metadata,
  created_at, updated_at) and an array of messages with role (as string),
  content, token_count, timestamp, and tool_calls.
  """
  @spec to_json(map()) :: binary()
  def to_json(conversation) do
    data = %{
      id: conversation.id,
      title: conversation.title,
      user_id: conversation.user_id,
      tags: conversation.tags,
      model: conversation.model,
      metadata: conversation.metadata,
      created_at: format_datetime(conversation.inserted_at),
      updated_at: format_datetime(conversation.updated_at),
      messages: Enum.map(conversation.messages || [], &serialize_message/1)
    }

    Jason.encode!(data, pretty: true)
  end

  @doc """
  Serializes a conversation to a Markdown document.

  Produces a human-readable document with a title heading, metadata
  summary line, chronological messages with role labels, and an export footer.
  """
  @spec to_markdown(map()) :: binary()
  def to_markdown(conversation) do
    cost = format_cost(conversation[:total_cost])
    message_count = conversation[:message_count] || length(conversation.messages || [])
    created_at = format_datetime_short(conversation.inserted_at)

    header = """
    # #{conversation.title}

    **Model:** #{conversation.model} | **Messages:** #{message_count} | **Cost:** $#{cost}
    **Created:** #{created_at}

    ---
    """

    messages_body =
      (conversation.messages || [])
      |> Enum.map(&render_message_markdown/1)
      |> Enum.join("\n")

    footer = "\n---\n*Exported from PhoenixFilamentAI on #{Date.utc_today()}*\n"

    header <> messages_body <> footer
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp serialize_message(message) do
    %{
      role: to_string(message.role),
      content: message.content,
      token_count: message.token_count,
      timestamp: format_datetime(message.inserted_at),
      tool_calls: message.tool_calls
    }
  end

  defp render_message_markdown(message) do
    role_label = message.role |> to_string() |> String.capitalize()
    time = format_time(message.inserted_at)
    content = message.content || ""

    token_info =
      if message.role == :assistant && message.token_count && message.token_count > 0 do
        " \u2014 *#{message.token_count} tokens*"
      else
        ""
      end

    """
    **#{role_label}** (#{time})#{token_info}:
    #{content}
    """
  end

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_datetime(%NaiveDateTime{} = ndt) do
    Calendar.strftime(ndt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_datetime_short(nil), do: "unknown"

  defp format_datetime_short(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end

  defp format_datetime_short(%NaiveDateTime{} = ndt) do
    Calendar.strftime(ndt, "%Y-%m-%d %H:%M")
  end

  defp format_time(nil), do: "?"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M")
  end

  defp format_time(%NaiveDateTime{} = ndt) do
    Calendar.strftime(ndt, "%H:%M")
  end

  defp format_cost(nil), do: "0.00"

  defp format_cost(%Decimal{} = d) do
    d
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp format_cost(other), do: to_string(other)
end
