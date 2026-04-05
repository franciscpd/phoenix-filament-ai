defmodule PhoenixFilamentAI.Components.MessageComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias PhoenixFilamentAI.Components.MessageComponent

  defp render_message(message, opts \\ []) do
    streaming = Keyword.get(opts, :streaming, false)
    on_retry = Keyword.get(opts, :on_retry, nil)

    assigns = %{message: message, streaming: streaming, on_retry: on_retry}

    rendered_to_string(~H"""
    <MessageComponent.message message={@message} streaming={@streaming} on_retry={@on_retry} />
    """)
  end

  describe "user messages" do
    test "renders user message with markdown" do
      html = render_message(%{role: :user, content: "Hello **world**"})
      assert html =~ "pfa-role-user"
      assert html =~ "pfa-message-user"
      assert html =~ "<strong>world</strong>"
    end

    test "renders user message with code" do
      html = render_message(%{role: :user, content: "Use `mix test`"})
      assert html =~ "<code>"
      assert html =~ "mix test"
    end
  end

  describe "assistant messages" do
    test "renders assistant message with markdown" do
      html = render_message(%{role: :assistant, content: "Here is **bold** text"})
      assert html =~ "pfa-role-assistant"
      assert html =~ "pfa-message-assistant"
      assert html =~ "<strong>bold</strong>"
    end

    test "renders assistant message in streaming mode" do
      html = render_message(%{role: :assistant, content: "Partial **text"}, streaming: true)
      assert html =~ "pfa-message-assistant"
      assert html =~ "text"
    end

    test "renders assistant message with code block" do
      content = """
      Here is some code:

      ```elixir
      IO.puts("hello")
      ```
      """

      html = render_message(%{role: :assistant, content: content})
      assert html =~ "pfa-message-assistant"
      assert html =~ "hello"
    end
  end

  describe "system messages" do
    test "renders system message as plain text banner" do
      html = render_message(%{role: :system, content: "System initialized"})
      assert html =~ "pfa-role-system"
      assert html =~ "pfa-message-system"
      assert html =~ "pfa-system-text"
      assert html =~ "System initialized"
      # System messages should NOT have markdown rendering
      refute html =~ "<p>"
    end
  end

  describe "error messages" do
    test "renders error message with error styling" do
      html = render_message(%{role: :error, content: "Something went wrong"})
      assert html =~ "pfa-role-error"
      assert html =~ "pfa-message-error"
      assert html =~ "pfa-error-icon"
      assert html =~ "Something went wrong"
    end

    test "renders retry button when on_retry is provided" do
      html = render_message(%{role: :error, content: "Failed"}, on_retry: "retry_message")
      assert html =~ "pfa-retry-btn"
      assert html =~ "Retry"
      assert html =~ "retry_message"
    end

    test "does not render retry button when on_retry is nil" do
      html = render_message(%{role: :error, content: "Failed"})
      refute html =~ "pfa-retry-btn"
      refute html =~ "Retry"
    end
  end

  describe "tool_call messages" do
    @endpoint PhoenixFilamentAI.TestEndpoint

    test "renders tool call card" do
      message = %{
        role: :tool_call,
        content: "",
        id: "tc-1",
        tool_name: "search",
        status: :completed,
        input: %{"query" => "elixir"},
        output: %{"results" => []}
      }

      html =
        render_component(&MessageComponent.message/1,
          message: message,
          streaming: false,
          on_retry: nil
        )

      assert html =~ "pfa-tool-call-card"
      assert html =~ "search"
      assert html =~ "Done"
    end

    test "renders tool call with running status" do
      message = %{
        role: :tool_call,
        content: "",
        id: "tc-2",
        tool_name: "fetch_data",
        status: :running
      }

      html =
        render_component(&MessageComponent.message/1,
          message: message,
          streaming: false,
          on_retry: nil
        )

      assert html =~ "pfa-tool-call-card"
      assert html =~ "fetch_data"
      assert html =~ "Running"
      assert html =~ "pfa-status-running"
    end

    test "renders tool call with failed status" do
      message = %{
        role: :tool_call,
        content: "",
        id: "tc-3",
        tool_name: "api_call",
        status: :failed
      }

      html =
        render_component(&MessageComponent.message/1,
          message: message,
          streaming: false,
          on_retry: nil
        )

      assert html =~ "Failed"
      assert html =~ "pfa-status-failed"
    end
  end

  describe "CSS class prefixing" do
    test "all classes use pfa- prefix" do
      for role <- [:user, :assistant, :system, :error] do
        html = render_message(%{role: role, content: "test"})
        assert html =~ "pfa-"
      end
    end

    test "role-specific classes are applied" do
      assert render_message(%{role: :user, content: "hi"}) =~ "pfa-role-user"
      assert render_message(%{role: :assistant, content: "hi"}) =~ "pfa-role-assistant"
      assert render_message(%{role: :system, content: "hi"}) =~ "pfa-role-system"
      assert render_message(%{role: :error, content: "hi"}) =~ "pfa-role-error"
    end
  end
end
