defmodule PhoenixFilamentAI.Chat.StreamHandlerTest do
  use ExUnit.Case, async: true

  alias PhoenixFilamentAI.Chat.StreamHandler

  describe "start/4" do
    test "returns a Task struct and passes to: option" do
      # Task.async links to caller, so trap exits to survive the Task crash
      Process.flag(:trap_exit, true)

      task = StreamHandler.start(:nonexistent_store, "conv-1", "hello", provider: :test)
      assert %Task{ref: ref} = task
      assert is_reference(ref)

      # The task will crash (no store running) — flush the messages
      Process.demonitor(ref, [:flush])

      receive do
        {:EXIT, _pid, _reason} -> :ok
      after
        2000 -> :ok
      end
    after
      Process.flag(:trap_exit, false)
    end
  end

  describe "classify_error/1" do
    test "classifies timeout errors as retriable" do
      assert StreamHandler.classify_error(:timeout) == :retriable
      assert StreamHandler.classify_error({:timeout, :recv}) == :retriable
    end

    test "classifies rate limit errors as retriable" do
      assert StreamHandler.classify_error(:rate_limit) == :retriable
      assert StreamHandler.classify_error(:rate_limited) == :retriable
    end

    test "classifies network errors as retriable" do
      assert StreamHandler.classify_error(:econnrefused) == :retriable
      assert StreamHandler.classify_error(:closed) == :retriable
    end

    test "classifies auth errors as fatal" do
      assert StreamHandler.classify_error(:invalid_api_key) == :fatal
      assert StreamHandler.classify_error(:unauthorized) == :fatal
    end

    test "classifies missing config as fatal" do
      assert StreamHandler.classify_error({:missing_option, :provider}) == :fatal
    end

    test "classifies provider_down as fatal" do
      assert StreamHandler.classify_error(:provider_down) == :fatal
    end

    test "classifies struct errors by status" do
      assert StreamHandler.classify_error(%{status: 401}) == :fatal
      assert StreamHandler.classify_error(%{status: 403}) == :fatal
      assert StreamHandler.classify_error(%{status: 429}) == :retriable
      assert StreamHandler.classify_error(%{status: 500}) == :retriable
      assert StreamHandler.classify_error(%{status: 503}) == :retriable
    end

    test "classifies guardrail violations as domain" do
      assert StreamHandler.classify_error(%{reason: :guardrail_violation}) == :domain
    end

    test "classifies policy violations as domain" do
      assert StreamHandler.classify_error(%{policy: :content_filter}) == :domain
    end

    test "classifies unknown atom errors as domain" do
      assert StreamHandler.classify_error(:some_unknown_error) == :domain
    end
  end

  describe "error_message/1" do
    test "returns human-readable message for timeout" do
      msg = StreamHandler.error_message(:timeout)
      assert msg =~ "timed out"
    end

    test "returns human-readable message for rate limit" do
      msg = StreamHandler.error_message(:rate_limit)
      assert msg =~ "Rate limit"
    end

    test "returns human-readable message for invalid_api_key" do
      msg = StreamHandler.error_message(:invalid_api_key)
      assert msg =~ "Invalid API key"
    end

    test "returns human-readable message for missing config" do
      msg = StreamHandler.error_message({:missing_option, :provider})
      assert msg =~ "provider"
    end

    test "returns human-readable message for unknown errors" do
      msg = StreamHandler.error_message(:econnrefused)
      assert is_binary(msg)
      assert String.length(msg) > 0
    end
  end
end
