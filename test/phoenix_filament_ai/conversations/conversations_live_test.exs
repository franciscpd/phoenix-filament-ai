defmodule PhoenixFilamentAI.ConversationsLiveTest do
  use ExUnit.Case, async: true

  alias PhoenixFilamentAI.ConversationsLive

  # -------------------------------------------------------------------
  # Module-level tests (structural verification)
  # -------------------------------------------------------------------

  describe "ConversationsLive module" do
    test "module is defined and is a LiveView" do
      Code.ensure_loaded!(ConversationsLive)

      assert function_exported?(ConversationsLive, :mount, 3)
      assert function_exported?(ConversationsLive, :handle_params, 3)
      assert function_exported?(ConversationsLive, :handle_event, 3)
      assert function_exported?(ConversationsLive, :handle_info, 2)
      assert function_exported?(ConversationsLive, :render, 1)
    end
  end
end
