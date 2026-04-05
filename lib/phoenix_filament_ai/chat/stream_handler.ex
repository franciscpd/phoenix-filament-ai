defmodule PhoenixFilamentAI.Chat.StreamHandler do
  @moduledoc """
  Manages the AI call lifecycle for chat threads.

  Launches a non-blocking task for `StoreAdapter.converse/4`, routing
  the result back to the calling process as `{:ai_complete, response}`
  or `{:ai_error, reason}`.

  ## Error Classification

  Errors are classified into three categories:

  - **retriable** — timeout, rate limit, network errors. The user can retry.
  - **fatal** — invalid API key, provider down. Requires intervention.
  - **domain** — guardrail violations, content policy. User should rephrase.

  ## Design

  `PhoenixAI.Store.converse/3` is synchronous — it runs the full pipeline
  (save user message, load history, memory, guardrails, AI call, save
  response) and returns `{:ok, response}` or `{:error, term()}`.

  We wrap it in a `Task` via the LiveView `start_async` pattern to keep
  the UI responsive. Streaming support can be layered on top when the
  upstream API supports it.
  """

  alias PhoenixFilamentAI.StoreAdapter

  require Logger

  @type error_class :: :retriable | :fatal | :domain

  @doc """
  Starts an async AI converse call, returning the task reference.

  The caller (typically a LiveComponent) should handle the result via
  `handle_async/3` callbacks.

  ## Options

  All options are forwarded to `StoreAdapter.converse/4`:
  - `:provider` — AI provider atom
  - `:model` — model string
  - `:api_key` — API key override
  - `:system` — system prompt
  - `:tools` — tool definitions
  - `:user_id` — user identifier
  """
  @spec start(atom(), String.t(), String.t(), keyword()) :: Task.t()
  def start(store, conversation_id, message, opts \\ []) do
    caller = self()

    Task.async(fn ->
      result = StoreAdapter.converse(store, conversation_id, message, opts)

      case result do
        {:ok, response} ->
          send(caller, {:ai_complete, response})
          {:ok, response}

        {:error, reason} ->
          send(caller, {:ai_error, reason})
          {:error, reason}
      end
    end)
  end

  @doc """
  Classifies an error reason into `:retriable`, `:fatal`, or `:domain`.
  """
  @spec classify_error(term()) :: error_class()
  def classify_error(reason) do
    case reason do
      :timeout ->
        :retriable

      :rate_limit ->
        :retriable

      :rate_limited ->
        :retriable

      {:timeout, _} ->
        :retriable

      :econnrefused ->
        :retriable

      :closed ->
        :retriable

      {:error, :timeout} ->
        :retriable

      {:error, :econnrefused} ->
        :retriable

      :invalid_api_key ->
        :fatal

      :unauthorized ->
        :fatal

      :provider_down ->
        :fatal

      {:missing_option, _} ->
        :fatal

      %{} = map when is_map(map) ->
        classify_map_error(map)

      reason when is_atom(reason) ->
        :domain

      _ ->
        :retriable
    end
  end

  defp classify_map_error(map) do
    cond do
      match?(%{status: status} when status in [401, 403], map) -> :fatal
      match?(%{status: status} when status in [429], map) -> :retriable
      match?(%{status: status} when status in [500, 502, 503], map) -> :retriable
      match?(%{reason: :guardrail_violation}, map) -> :domain
      match?(%{policy: _}, map) -> :domain
      true -> :retriable
    end
  end

  @doc """
  Returns a human-readable error message for a given error reason.
  """
  @spec error_message(term()) :: String.t()
  def error_message(reason) do
    case classify_error(reason) do
      :retriable ->
        retriable_message(reason)

      :fatal ->
        fatal_message(reason)

      :domain ->
        domain_message(reason)
    end
  end

  defp retriable_message(:timeout), do: "The request timed out. Please try again."
  defp retriable_message({:timeout, _}), do: "The request timed out. Please try again."

  defp retriable_message(:rate_limit),
    do: "Rate limit reached. Please wait a moment and try again."

  defp retriable_message(:rate_limited),
    do: "Rate limit reached. Please wait a moment and try again."

  defp retriable_message(_), do: "A temporary error occurred. Please try again."

  defp fatal_message(:invalid_api_key), do: "Invalid API key. Please check your configuration."
  defp fatal_message(:unauthorized), do: "Authentication failed. Please check your API key."

  defp fatal_message({:missing_option, opt}),
    do: "Missing configuration: #{opt}. Please check your setup."

  defp fatal_message(_), do: "A configuration error occurred. Please contact your administrator."

  defp domain_message(reason) when is_atom(reason) do
    reason
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> then(&"Your message could not be processed: #{&1}.")
  end

  defp domain_message(%{reason: reason}) when is_binary(reason) do
    "Your message could not be processed: #{reason}."
  end

  defp domain_message(_), do: "Your message could not be processed. Please try rephrasing."
end
