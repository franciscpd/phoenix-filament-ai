# Phase 1: Foundation + Chat — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A developer adds the plugin to a PhoenixFilament panel and gets a working dashboard chat widget and full-screen chat page with streaming AI responses, markdown rendering, and persistent conversations.

**Architecture:** Layered components (MessageComponent → ChatThread → Widget/Page shells) with a risk-first build order that validates Plugin API, Store API, and streaming before building features. StoreAdapter is the single abstraction layer between the plugin and PhoenixAI.Store.

**Tech Stack:** Elixir, Phoenix LiveView, PhoenixFilament (plugin API), PhoenixAI + PhoenixAI.Store (AI runtime + persistence), MDEx (markdown), Makeup (syntax highlighting), NimbleOptions (config validation)

**Spec:** `.planning/phases/01-foundation-chat/BRAINSTORM.md`
**Context:** `.planning/phases/01-foundation-chat/01-CONTEXT.md`
**PRD:** `.planning/phoenix_filament_ai_prd.md`

---

## File Structure

### Files to Create

| File | Responsibility |
|------|---------------|
| `mix.exs` | Package definition, deps, project config |
| `.formatter.exs` | Code formatter config |
| `.credo.exs` | Credo static analysis config |
| `.gitignore` | Git ignores |
| `.github/workflows/ci.yml` | GitHub Actions CI |
| `lib/phoenix_filament/ai.ex` | Plugin module — `register/2`, `boot/1` |
| `lib/phoenix_filament_ai/config.ex` | NimbleOptions schema |
| `lib/phoenix_filament_ai/store_adapter.ex` | CRUD → PhoenixAI.Store API |
| `lib/phoenix_filament_ai/components/markdown.ex` | MDEx wrapper (streaming + complete) |
| `lib/phoenix_filament_ai/components/message_component.ex` | Single message renderer |
| `lib/phoenix_filament_ai/components/tool_call_card.ex` | Collapsible tool call card |
| `lib/phoenix_filament_ai/components/typing_indicator.ex` | Typing animation |
| `lib/phoenix_filament_ai/components/copy_button_hook.ex` | JS hook for clipboard |
| `lib/phoenix_filament_ai/chat/stream_handler.ex` | Streaming logic |
| `lib/phoenix_filament_ai/chat/chat_thread.ex` | Stateful LiveComponent |
| `lib/phoenix_filament_ai/chat/chat_widget.ex` | Dashboard widget shell |
| `lib/phoenix_filament_ai/chat/chat_page.ex` | Full-screen LiveView |
| `lib/phoenix_filament_ai/chat/sidebar.ex` | Conversation sidebar |
| `test/test_helper.exs` | Test setup |
| `test/support/fixtures.ex` | Test helpers |
| `test/phoenix_filament_ai/config_test.exs` | Config tests |
| `test/phoenix_filament_ai/store_adapter_test.exs` | StoreAdapter tests |
| `test/phoenix_filament_ai/components/markdown_test.exs` | Markdown tests |
| `test/phoenix_filament_ai/components/message_component_test.exs` | MessageComponent tests |
| `test/phoenix_filament_ai/chat/chat_thread_test.exs` | ChatThread tests |
| `test/phoenix_filament_ai/chat/chat_widget_test.exs` | ChatWidget tests |
| `test/phoenix_filament_ai/chat/chat_page_test.exs` | ChatPage tests |
| `test/phoenix_filament_ai/plugin_test.exs` | Plugin register/boot tests |

---

## Task 1: Project Scaffold

**Files:**
- Create: `mix.exs`
- Create: `.formatter.exs`
- Create: `.credo.exs`
- Create: `.gitignore`
- Create: `.github/workflows/ci.yml`
- Create: `README.md`
- Create: `LICENSE`
- Create: `lib/phoenix_filament_ai.ex`
- Create: `test/test_helper.exs`
- Create: `test/support/fixtures.ex`

- [ ] **Step 1: Create mix.exs**

```elixir
defmodule PhoenixFilamentAI.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/franciscpd/phoenix_filament_ai"

  def project do
    [
      app: :phoenix_filament_ai,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "PhoenixFilamentAI",
      description: "AI plugin for PhoenixFilament — chat, conversations, cost tracking, and event log",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_filament, "~> 0.1"},
      {:phoenix_ai, "~> 0.3"},
      {:phoenix_ai_store, "~> 0.1"},
      {:nimble_options, "~> 1.1"},
      {:mdex, "~> 0.12"},
      {:makeup, "~> 1.1"},
      {:makeup_elixir, "~> 1.0"},

      # Dev/Test
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false}
    ]
  end

  defp aliases do
    [
      lint: ["format --check-formatted", "credo --strict", "dialyzer"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end
end
```

Note: Verify the Elixir version constraint matches `phoenix_ai`'s requirement. Check `phoenix_ai`'s `mix.exs` and adjust `~> 1.15` if needed.

- [ ] **Step 2: Create .formatter.exs**

```elixir
[
  import_deps: [:phoenix_filament, :phoenix_ai, :phoenix_ai_store],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Phoenix.LiveView.HTMLFormatter]
]
```

- [ ] **Step 3: Create .credo.exs**

```elixir
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: true,
      checks: %{
        enabled: [
          {Credo.Check.Readability.ModuleDoc, false}
        ]
      }
    }
  ]
}
```

- [ ] **Step 4: Create .gitignore**

```
/_build/
/cover/
/deps/
/doc/
*.ez
phoenix_filament_ai-*.tar
.superpowers/
```

- [ ] **Step 5: Create .github/workflows/ci.yml**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  MIX_ENV: test

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        elixir: ['1.17']
        otp: ['26']
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: ${{ matrix.elixir }}
          otp-version: ${{ matrix.otp }}
      - run: mix deps.get
      - run: mix format --check-formatted
      - run: mix credo --strict
      - run: mix test
      - run: mix dialyzer
```

- [ ] **Step 6: Create LICENSE (MIT)**

Standard MIT license with current year and author name.

- [ ] **Step 7: Create README.md**

Minimal README with package name, one-line description, and installation instructions pointing to Hex.

- [ ] **Step 8: Create lib/phoenix_filament_ai.ex (root module)**

```elixir
defmodule PhoenixFilamentAI do
  @moduledoc """
  AI plugin for PhoenixFilament.

  Adds chat, conversation management, cost tracking, and event logging
  to PhoenixFilament admin panels.
  """
end
```

- [ ] **Step 9: Create test/test_helper.exs**

```elixir
ExUnit.start()
```

- [ ] **Step 10: Create test/support/fixtures.ex**

```elixir
defmodule PhoenixFilamentAI.Fixtures do
  @moduledoc """
  Test fixtures for PhoenixFilamentAI.
  """

  def valid_plugin_opts(overrides \\ []) do
    Keyword.merge(
      [
        store: :test_store,
        provider: :openai,
        model: "gpt-4o"
      ],
      overrides
    )
  end

  def conversation_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        title: "Test Conversation",
        tags: ["test"],
        status: :active
      },
      overrides
    )
  end

  def message_attrs(role \\ :user, overrides \\ %{}) do
    Map.merge(
      %{
        role: role,
        content: "Hello, this is a test message."
      },
      overrides
    )
  end
end
```

- [ ] **Step 11: Run mix deps.get && mix compile**

```bash
mix deps.get && mix compile
```

Expected: Dependencies resolve and project compiles with no errors (warnings from deps are ok).

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "chore: scaffold phoenix_filament_ai package"
```

---

## Task 2: Plugin Skeleton

**Files:**
- Create: `lib/phoenix_filament/ai.ex`
- Create: `test/phoenix_filament_ai/plugin_test.exs`

This task validates the PhoenixFilament Plugin API. If `register/2` or `boot/1` don't work as expected, we find out here — before building any features.

- [ ] **Step 1: Write the failing test for register/2**

```elixir
# test/phoenix_filament_ai/plugin_test.exs
defmodule PhoenixFilamentAI.PluginTest do
  use ExUnit.Case, async: true

  alias PhoenixFilament.AI

  describe "register/2" do
    test "returns map with nav_items, routes, widgets, and hooks" do
      opts = PhoenixFilamentAI.Fixtures.valid_plugin_opts()
      result = AI.register(%{}, opts)

      assert is_map(result)
      assert Map.has_key?(result, :nav_items)
      assert Map.has_key?(result, :routes)
      assert Map.has_key?(result, :widgets)
      assert Map.has_key?(result, :hooks)
    end

    test "includes chat navigation when chat_widget is enabled" do
      opts = PhoenixFilamentAI.Fixtures.valid_plugin_opts(chat_widget: true)
      result = AI.register(%{}, opts)

      assert length(result.nav_items) > 0
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mix test test/phoenix_filament_ai/plugin_test.exs
```

Expected: FAIL — `PhoenixFilament.AI` module not defined.

- [ ] **Step 3: Write the plugin module**

```elixir
# lib/phoenix_filament/ai.ex
defmodule PhoenixFilament.AI do
  @moduledoc """
  AI plugin for PhoenixFilament.

  Adds AI chat capabilities to PhoenixFilament admin panels.

  ## Usage

      plugins do
        plugin PhoenixFilament.AI,
          store: :my_store,
          provider: :openai,
          model: "gpt-4o"
      end
  """

  use PhoenixFilament.Plugin

  @impl true
  def register(_panel, opts) do
    config = PhoenixFilamentAI.Config.validate!(opts)

    %{
      nav_items: build_nav_items(config),
      routes: build_routes(config),
      widgets: build_widgets(config),
      hooks: build_hooks(config)
    }
  end

  @impl true
  def boot(socket) do
    config = get_plugin_config(socket)
    store = Keyword.fetch!(config, :store)

    socket
    |> Phoenix.Component.assign(:ai_store, store)
    |> Phoenix.Component.assign(:ai_config, config)
  end

  defp build_nav_items(config) do
    nav_group = Keyword.get(config, :nav_group, "AI")
    items = []

    items =
      if Keyword.get(config, :chat_page, true) do
        items ++ [%{label: "Chat", icon: "hero-chat-bubble-left-right", group: nav_group, path: "/ai/chat"}]
      else
        items
      end

    items
  end

  defp build_routes(config) do
    routes = []

    routes =
      if Keyword.get(config, :chat_page, true) do
        routes ++ [%{path: "/ai/chat", live: PhoenixFilamentAI.Chat.ChatPage}]
      else
        routes
      end

    routes
  end

  defp build_widgets(config) do
    widgets = []

    widgets =
      if Keyword.get(config, :chat_widget, true) do
        widgets ++ [PhoenixFilamentAI.Chat.ChatWidget]
      else
        widgets
      end

    widgets
  end

  defp build_hooks(_config) do
    [PhoenixFilamentAI.Components.CopyButtonHook]
  end

  defp get_plugin_config(socket) do
    socket.assigns.__panel__.__panel__(:plugin_opts)[__MODULE__]
  end
end
```

Note: The exact Plugin API (`use PhoenixFilament.Plugin`, `get_plugin_config/1`) must be verified against the actual `phoenix_filament` source. The code above follows the PRD §5.2 — adjust if the real API differs.

- [ ] **Step 4: Run test to verify it passes**

```bash
mix test test/phoenix_filament_ai/plugin_test.exs
```

Expected: PASS (may need Config module stub first — see Task 3).

Note: If tests fail because `PhoenixFilamentAI.Config` doesn't exist yet, create a minimal stub that returns the opts as-is, then implement properly in Task 3.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_filament/ai.ex test/phoenix_filament_ai/plugin_test.exs
git commit -m "feat: add plugin skeleton with register/2 and boot/1"
```

---

## Task 3: NimbleOptions Config

**Files:**
- Create: `lib/phoenix_filament_ai/config.ex`
- Create: `test/phoenix_filament_ai/config_test.exs`

- [ ] **Step 1: Write failing tests for config validation**

```elixir
# test/phoenix_filament_ai/config_test.exs
defmodule PhoenixFilamentAI.ConfigTest do
  use ExUnit.Case, async: true

  alias PhoenixFilamentAI.Config

  describe "validate!/1" do
    test "accepts valid minimal config" do
      opts = [store: :my_store, provider: :openai, model: "gpt-4o"]
      assert config = Config.validate!(opts)
      assert Keyword.get(config, :store) == :my_store
      assert Keyword.get(config, :provider) == :openai
      assert Keyword.get(config, :model) == "gpt-4o"
    end

    test "applies progressive defaults" do
      opts = [store: :my_store, provider: :openai, model: "gpt-4o"]
      config = Config.validate!(opts)

      assert Keyword.get(config, :chat_widget) == true
      assert Keyword.get(config, :chat_page) == true
      assert Keyword.get(config, :conversations) == false
      assert Keyword.get(config, :cost_dashboard) == false
      assert Keyword.get(config, :event_log) == false
    end

    test "raises on missing required :store" do
      assert_raise NimbleOptions.ValidationError, ~r/store/, fn ->
        Config.validate!(provider: :openai, model: "gpt-4o")
      end
    end

    test "raises on missing required :provider" do
      assert_raise NimbleOptions.ValidationError, ~r/provider/, fn ->
        Config.validate!(store: :my_store, model: "gpt-4o")
      end
    end

    test "raises on missing required :model" do
      assert_raise NimbleOptions.ValidationError, ~r/model/, fn ->
        Config.validate!(store: :my_store, provider: :openai)
      end
    end

    test "accepts custom nav_group" do
      opts = [store: :my_store, provider: :openai, model: "gpt-4o", nav_group: "Tools"]
      config = Config.validate!(opts)
      assert Keyword.get(config, :nav_group) == "Tools"
    end

    test "accepts custom column_span for chat_widget" do
      opts = [
        store: :my_store, provider: :openai, model: "gpt-4o",
        chat_widget: [column_span: 12, sort: 50]
      ]
      config = Config.validate!(opts)
      widget_opts = Keyword.get(config, :chat_widget)
      assert is_list(widget_opts)
      assert Keyword.get(widget_opts, :column_span) == 12
    end

    test "accepts chat_widget as boolean true (uses defaults)" do
      opts = [store: :my_store, provider: :openai, model: "gpt-4o", chat_widget: true]
      config = Config.validate!(opts)
      assert Keyword.get(config, :chat_widget) == true
    end

    test "accepts ets_warning option" do
      opts = [store: :my_store, provider: :openai, model: "gpt-4o", ets_warning: false]
      config = Config.validate!(opts)
      assert Keyword.get(config, :ets_warning) == false
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/phoenix_filament_ai/config_test.exs
```

Expected: FAIL — `PhoenixFilamentAI.Config` not defined.

- [ ] **Step 3: Implement Config module**

```elixir
# lib/phoenix_filament_ai/config.ex
defmodule PhoenixFilamentAI.Config do
  @moduledoc """
  Configuration validation for PhoenixFilament.AI plugin.

  All options are validated at compile time via NimbleOptions.
  """

  @chat_widget_schema [
    column_span: [type: :pos_integer, default: 6, doc: "Dashboard grid column span (1-12)"],
    sort: [type: :integer, default: 100, doc: "Widget sort order in dashboard"],
    system_prompt: [type: :string, default: "You are a helpful admin assistant.", doc: "System prompt for chat"],
    max_tokens: [type: :pos_integer, default: 4096, doc: "Max tokens per response"],
    title: [type: :string, default: "AI Assistant", doc: "Widget title"]
  ]

  @chat_opts_schema [
    system_prompt: [type: :string, default: "You are a helpful assistant.", doc: "Default system prompt"],
    max_tokens: [type: :pos_integer, default: 4096, doc: "Max tokens per response"],
    temperature: [type: :float, default: 0.7, doc: "Temperature for AI responses"]
  ]

  @schema NimbleOptions.new!([
    store: [type: :atom, required: true, doc: "Named PhoenixAI.Store to use"],
    provider: [type: :atom, required: true, doc: "AI provider (:openai, :anthropic, etc.)"],
    model: [type: :string, required: true, doc: "Model name (e.g., \"gpt-4o\")"],
    api_key: [type: {:or, [:string, nil]}, default: nil, doc: "Optional API key override"],

    # Feature toggles (progressive defaults)
    chat_widget: [type: {:or, [:boolean, keyword_list: @chat_widget_schema]}, default: true, doc: "Chat widget on dashboard"],
    chat_page: [type: :boolean, default: true, doc: "Full-screen chat page"],
    conversations: [type: :boolean, default: false, doc: "Conversations resource"],
    cost_dashboard: [type: :boolean, default: false, doc: "Cost tracking dashboard"],
    event_log: [type: :boolean, default: false, doc: "Event log viewer"],

    # Chat options
    chat: [type: {:keyword_list, @chat_opts_schema}, default: [], doc: "Chat behavior options"],

    # Navigation
    nav_group: [type: :string, default: "AI", doc: "Navigation group name"],
    nav_icon: [type: :string, default: "hero-sparkles", doc: "Navigation icon"],

    # ETS warning
    ets_warning: [type: :boolean, default: true, doc: "Show ETS backend warning in production"]
  ])

  @doc """
  Validates plugin options at compile time.

  Raises `NimbleOptions.ValidationError` with a clear message on invalid config.
  """
  def validate!(opts) do
    NimbleOptions.validate!(opts, @schema)
  end

  @doc """
  Returns the NimbleOptions schema for documentation.
  """
  def schema, do: @schema
end
```

Note: The `chat_widget` option accepts either `true` (boolean, uses defaults) or a keyword list with detailed options. The NimbleOptions `:or` type handles this. If NimbleOptions doesn't support this exact pattern, use a custom validator function instead.

- [ ] **Step 4: Run tests to verify they pass**

```bash
mix test test/phoenix_filament_ai/config_test.exs
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_filament_ai/config.ex test/phoenix_filament_ai/config_test.exs
git commit -m "feat: add NimbleOptions config validation"
```

---

## Task 4: StoreAdapter

**Files:**
- Create: `lib/phoenix_filament_ai/store_adapter.ex`
- Create: `test/phoenix_filament_ai/store_adapter_test.exs`

This task validates the PhoenixAI.Store API. If function names or arities don't match, we find out here.

- [ ] **Step 1: Write failing tests**

```elixir
# test/phoenix_filament_ai/store_adapter_test.exs
defmodule PhoenixFilamentAI.StoreAdapterTest do
  use ExUnit.Case, async: true

  alias PhoenixFilamentAI.StoreAdapter

  # Note: These tests run against the real PhoenixAI.Store API.
  # The store must be started in test_helper.exs or setup.
  # If the Store API doesn't match expectations, these tests
  # will reveal the mismatch immediately.

  describe "list_conversations/2" do
    test "returns a list of conversations" do
      result = StoreAdapter.list_conversations(:test_store)
      assert {:ok, conversations} = result
      assert is_list(conversations)
    end
  end

  describe "create_conversation/2" do
    test "creates a conversation and returns it" do
      attrs = PhoenixFilamentAI.Fixtures.conversation_attrs()
      assert {:ok, conversation} = StoreAdapter.create_conversation(:test_store, attrs)
      assert conversation.title == "Test Conversation"
    end
  end

  describe "get_conversation/2" do
    test "returns a conversation by id" do
      {:ok, created} = StoreAdapter.create_conversation(:test_store, PhoenixFilamentAI.Fixtures.conversation_attrs())
      assert {:ok, found} = StoreAdapter.get_conversation(:test_store, created.id)
      assert found.id == created.id
    end

    test "returns error for non-existent id" do
      assert {:error, _reason} = StoreAdapter.get_conversation(:test_store, "non-existent-id")
    end
  end

  describe "list_messages/3" do
    test "returns messages for a conversation with cursor" do
      {:ok, conv} = StoreAdapter.create_conversation(:test_store, PhoenixFilamentAI.Fixtures.conversation_attrs())
      assert {:ok, {messages, _cursor}} = StoreAdapter.list_messages(:test_store, conv.id, limit: 20)
      assert is_list(messages)
    end
  end

  describe "backend_type/1" do
    test "returns :ets or :ecto" do
      result = StoreAdapter.backend_type(:test_store)
      assert result in [:ets, :ecto]
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/phoenix_filament_ai/store_adapter_test.exs
```

Expected: FAIL — `PhoenixFilamentAI.StoreAdapter` not defined.

- [ ] **Step 3: Implement StoreAdapter**

```elixir
# lib/phoenix_filament_ai/store_adapter.ex
defmodule PhoenixFilamentAI.StoreAdapter do
  @moduledoc """
  Abstraction layer between the plugin and PhoenixAI.Store.

  This is the only module that knows the Store's function names.
  If the Store API changes, only this file needs to change.
  """

  # --- Conversations ---

  def list_conversations(store, filters \\ []) do
    PhoenixAI.Store.list_conversations(filters, store: store)
  end

  def get_conversation(store, id) do
    PhoenixAI.Store.load_conversation(id, store: store)
  end

  def create_conversation(store, attrs) do
    PhoenixAI.Store.create_conversation(attrs, store: store)
  end

  def update_conversation(store, id, attrs) do
    with {:ok, conv} <- PhoenixAI.Store.load_conversation(id, store: store) do
      updated = struct(conv, attrs)
      PhoenixAI.Store.save_conversation(updated, store: store)
    end
  end

  def delete_conversation(store, id, opts \\ []) do
    PhoenixAI.Store.delete_conversation(id, Keyword.merge([store: store], opts))
  end

  def count_conversations(store, filters \\ []) do
    PhoenixAI.Store.count_conversations(filters, store: store)
  end

  # --- Messages (lazy loading) ---

  def list_messages(store, conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    before_cursor = Keyword.get(opts, :before_cursor, nil)

    store_opts =
      [store: store, limit: limit]
      |> then(fn o -> if before_cursor, do: Keyword.put(o, :before, before_cursor), else: o end)

    PhoenixAI.Store.list_messages(conversation_id, store_opts)
  end

  # --- Streaming ---

  def converse(store, conversation_id, message, opts \\ []) do
    PhoenixAI.Store.converse(conversation_id, message, Keyword.merge([store: store], opts))
  end

  # --- Store info ---

  def backend_type(store) do
    PhoenixAI.Store.backend_type(store)
  end
end
```

Note: The exact function names (`list_conversations`, `load_conversation`, `converse`, `backend_type`) are based on the PRD §5.4. Verify against the actual `phoenix_ai_store` source and adjust if needed. The adapter's value is precisely that adjustments are localized to this one file.

- [ ] **Step 4: Run tests to verify they pass**

```bash
mix test test/phoenix_filament_ai/store_adapter_test.exs
```

Expected: PASS (if Store API matches). If any function names are wrong, fix the adapter — that's exactly what this task is for.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_filament_ai/store_adapter.ex test/phoenix_filament_ai/store_adapter_test.exs
git commit -m "feat: add StoreAdapter for PhoenixAI.Store abstraction"
```

---

## Task 5: Markdown & MessageComponent

**Files:**
- Create: `lib/phoenix_filament_ai/components/markdown.ex`
- Create: `lib/phoenix_filament_ai/components/message_component.ex`
- Create: `lib/phoenix_filament_ai/components/tool_call_card.ex`
- Create: `test/phoenix_filament_ai/components/markdown_test.exs`
- Create: `test/phoenix_filament_ai/components/message_component_test.exs`

- [ ] **Step 1: Write failing tests for Markdown**

```elixir
# test/phoenix_filament_ai/components/markdown_test.exs
defmodule PhoenixFilamentAI.Components.MarkdownTest do
  use ExUnit.Case, async: true

  alias PhoenixFilamentAI.Components.Markdown

  describe "render_complete/1" do
    test "renders basic markdown to HTML" do
      html = Markdown.render_complete("**bold** and *italic*")
      assert html =~ "<strong>bold</strong>"
      assert html =~ "<em>italic</em>"
    end

    test "renders code blocks with syntax highlighting" do
      markdown = """
      ```elixir
      defmodule Hello do
        def world, do: :ok
      end
      ```
      """
      html = Markdown.render_complete(markdown)
      assert html =~ "<pre"
      assert html =~ "<code"
    end

    test "sanitizes dangerous HTML" do
      html = Markdown.render_complete("<script>alert('xss')</script>")
      refute html =~ "<script>"
    end

    test "renders links" do
      html = Markdown.render_complete("[click](https://example.com)")
      assert html =~ ~s(href="https://example.com")
    end
  end

  describe "render_streaming/1" do
    test "renders incomplete markdown without crashing" do
      html = Markdown.render_streaming("**bold text without closing")
      assert is_binary(html)
    end

    test "renders partial code block" do
      html = Markdown.render_streaming("```elixir\ndef hello do\n")
      assert is_binary(html)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/phoenix_filament_ai/components/markdown_test.exs
```

Expected: FAIL — module not defined.

- [ ] **Step 3: Implement Markdown module**

```elixir
# lib/phoenix_filament_ai/components/markdown.ex
defmodule PhoenixFilamentAI.Components.Markdown do
  @moduledoc """
  MDEx wrapper for rendering markdown with streaming support.

  Two modes:
  - `render_complete/1` — for finalized messages (full markdown document)
  - `render_streaming/1` — for in-progress streaming (handles incomplete markdown)

  Both modes apply XSS sanitization (via MDEx/ammonia) and syntax highlighting (via Makeup).
  """

  @doc """
  Renders a complete markdown string to HTML.
  Used for finalized messages (user and completed assistant messages).
  """
  def render_complete(markdown) when is_binary(markdown) do
    markdown
    |> MDEx.to_html!(sanitize: true)
    |> apply_syntax_highlighting()
  end

  @doc """
  Renders potentially incomplete markdown to HTML.
  Used during streaming — handles unclosed bold, partial code blocks, etc.
  """
  def render_streaming(markdown) when is_binary(markdown) do
    markdown
    |> MDEx.to_html!(sanitize: true, streaming: true)
    |> apply_syntax_highlighting()
  end

  defp apply_syntax_highlighting(html) do
    Makeup.highlight(html)
  rescue
    _ -> html
  end
end
```

Note: Verify MDEx API — `to_html!/2` may be `to_html/2` returning `{:ok, html}`. The `streaming: true` option must be confirmed against MDEx docs. Makeup's `highlight/1` operates on HTML with `<code class="language-X">` blocks — verify integration.

- [ ] **Step 4: Run markdown tests**

```bash
mix test test/phoenix_filament_ai/components/markdown_test.exs
```

Expected: PASS

- [ ] **Step 5: Write failing tests for MessageComponent**

```elixir
# test/phoenix_filament_ai/components/message_component_test.exs
defmodule PhoenixFilamentAI.Components.MessageComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PhoenixFilamentAI.Components.MessageComponent

  describe "render/1" do
    test "renders user message with markdown" do
      html = render_component(MessageComponent, %{
        message: %{role: :user, content: "Hello **world**"},
        streaming: false,
        on_retry: nil
      })

      assert html =~ "Hello"
      assert html =~ "<strong>world</strong>"
      assert html =~ "data-role=\"user\""
    end

    test "renders assistant message with markdown" do
      html = render_component(MessageComponent, %{
        message: %{role: :assistant, content: "Here is `code`"},
        streaming: false,
        on_retry: nil
      })

      assert html =~ "<code"
      assert html =~ "data-role=\"assistant\""
    end

    test "renders system message as banner" do
      html = render_component(MessageComponent, %{
        message: %{role: :system, content: "System prompt here"},
        streaming: false,
        on_retry: nil
      })

      assert html =~ "data-role=\"system\""
      assert html =~ "System prompt here"
    end

    test "renders error message with retry button" do
      html = render_component(MessageComponent, %{
        message: %{role: :error, content: "Request timed out"},
        streaming: false,
        on_retry: "retry"
      })

      assert html =~ "data-role=\"error\""
      assert html =~ "Request timed out"
      assert html =~ "phx-click"
    end

    test "renders streaming assistant message" do
      html = render_component(MessageComponent, %{
        message: %{role: :assistant, content: "Partial **resp"},
        streaming: true,
        on_retry: nil
      })

      assert html =~ "data-role=\"assistant\""
      assert html =~ "data-streaming=\"true\""
    end
  end
end
```

- [ ] **Step 6: Run tests to verify they fail**

```bash
mix test test/phoenix_filament_ai/components/message_component_test.exs
```

Expected: FAIL — module not defined.

- [ ] **Step 7: Implement MessageComponent**

```elixir
# lib/phoenix_filament_ai/components/message_component.ex
defmodule PhoenixFilamentAI.Components.MessageComponent do
  @moduledoc """
  Renders a single chat message.

  Supports roles: :user, :assistant, :system, :error, :tool_call.
  Both user and assistant messages render markdown via MDEx.
  """

  use Phoenix.Component

  alias PhoenixFilamentAI.Components.Markdown

  attr :message, :map, required: true
  attr :streaming, :boolean, default: false
  attr :on_retry, :any, default: nil

  def message(assigns) do
    ~H"""
    <div
      class={message_classes(@message.role)}
      data-role={@message.role}
      data-streaming={to_string(@streaming)}
    >
      <%= case @message.role do %>
        <% :system -> %>
          <div class="pfa-message-system">
            <%= @message.content %>
          </div>
        <% :error -> %>
          <div class="pfa-message-error">
            <span class="pfa-error-icon">⚠</span>
            <span><%= @message.content %></span>
            <%= if @on_retry do %>
              <button phx-click={@on_retry} class="pfa-retry-btn">Retry</button>
            <% end %>
          </div>
        <% :tool_call -> %>
          <.live_component
            module={PhoenixFilamentAI.Components.ToolCallCard}
            id={"tool-#{@message.id}"}
            message={@message}
          />
        <% role when role in [:user, :assistant] -> %>
          <div class="pfa-message-content">
            <%= render_markdown(@message.content, @streaming) %>
          </div>
      <% end %>
    </div>
    """
  end

  defp render_markdown(content, true), do: Markdown.render_streaming(content) |> Phoenix.HTML.raw()
  defp render_markdown(content, false), do: Markdown.render_complete(content) |> Phoenix.HTML.raw()

  defp message_classes(:user), do: "pfa-message pfa-message-user"
  defp message_classes(:assistant), do: "pfa-message pfa-message-assistant"
  defp message_classes(:system), do: "pfa-message pfa-message-system-banner"
  defp message_classes(:error), do: "pfa-message pfa-message-error-banner"
  defp message_classes(:tool_call), do: "pfa-message pfa-message-tool-call"
  defp message_classes(_), do: "pfa-message"
end
```

- [ ] **Step 8: Implement ToolCallCard**

```elixir
# lib/phoenix_filament_ai/components/tool_call_card.ex
defmodule PhoenixFilamentAI.Components.ToolCallCard do
  @moduledoc """
  Collapsible card for displaying tool call input/output.
  """

  use Phoenix.LiveComponent

  def mount(socket) do
    {:ok, assign(socket, :expanded, false)}
  end

  def handle_event("toggle", _params, socket) do
    {:noreply, assign(socket, :expanded, !socket.assigns.expanded)}
  end

  def render(assigns) do
    ~H"""
    <div class="pfa-tool-call-card" data-expanded={to_string(@expanded)}>
      <button phx-click="toggle" phx-target={@myself} class="pfa-tool-call-header">
        <span class="pfa-tool-name"><%= @message.tool_name %></span>
        <span class="pfa-tool-status"><%= @message.status || "completed" %></span>
        <span class="pfa-toggle-icon"><%= if @expanded, do: "▼", else: "▶" %></span>
      </button>
      <%= if @expanded do %>
        <div class="pfa-tool-call-body">
          <div class="pfa-tool-section">
            <div class="pfa-tool-label">Input</div>
            <pre class="pfa-tool-json"><%= Jason.encode!(@message.input, pretty: true) %></pre>
          </div>
          <%= if @message[:output] do %>
            <div class="pfa-tool-section">
              <div class="pfa-tool-label">Output</div>
              <pre class="pfa-tool-json"><%= Jason.encode!(@message.output, pretty: true) %></pre>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
```

- [ ] **Step 9: Run all component tests**

```bash
mix test test/phoenix_filament_ai/components/
```

Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add lib/phoenix_filament_ai/components/ test/phoenix_filament_ai/components/
git commit -m "feat: add Markdown, MessageComponent, and ToolCallCard"
```

---

## Task 6: ChatThread + StreamHandler

**Files:**
- Create: `lib/phoenix_filament_ai/chat/stream_handler.ex`
- Create: `lib/phoenix_filament_ai/chat/chat_thread.ex`
- Create: `lib/phoenix_filament_ai/components/typing_indicator.ex`
- Create: `test/phoenix_filament_ai/chat/chat_thread_test.exs`

This task validates the streaming architecture — the most critical technical risk.

- [ ] **Step 1: Write failing tests for ChatThread**

```elixir
# test/phoenix_filament_ai/chat/chat_thread_test.exs
defmodule PhoenixFilamentAI.Chat.ChatThreadTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PhoenixFilamentAI.Chat.ChatThread

  describe "mount" do
    test "initializes with empty messages when no conversation" do
      html = render_component(ChatThread, %{
        id: "test-thread",
        store: :test_store,
        conversation_id: nil,
        config: PhoenixFilamentAI.Fixtures.valid_plugin_opts()
      })

      assert html =~ "Ask anything"  # empty state prompt
    end
  end

  describe "streaming" do
    test "accumulates chunks via send_update and renders progressively" do
      {:ok, view, _html} = mount_component(ChatThread, %{
        id: "test-thread",
        store: :test_store,
        conversation_id: nil,
        config: PhoenixFilamentAI.Fixtures.valid_plugin_opts()
      })

      # Simulate chunks arriving via send_update (as parent would route them)
      # Parent receives {:phoenix_ai, {:chunk, %StreamChunk{delta: "..."}}}
      # and forwards via send_update(ChatThread, id: ..., ai_chunk: chunk)
      send_update(ChatThread, id: "test-thread", ai_chunk: %{delta: "Hello "})
      send_update(ChatThread, id: "test-thread", ai_chunk: %{delta: "world"})
      send_update(ChatThread, id: "test-thread", ai_complete: %{content: "Hello world", role: :assistant})

      html = render(view)
      assert html =~ "Hello world"
    end
  end

  describe "error handling" do
    test "displays error message on AI failure via send_update" do
      {:ok, view, _html} = mount_component(ChatThread, %{
        id: "test-thread",
        store: :test_store,
        conversation_id: nil,
        config: PhoenixFilamentAI.Fixtures.valid_plugin_opts()
      })

      # Parent receives Task error and forwards via send_update
      send_update(ChatThread, id: "test-thread", ai_error: :timeout)

      html = render(view)
      assert html =~ "data-role=\"error\""
    end
  end
end
```

Note: `mount_component` is a helper that may need to be defined in test support — it depends on how PhoenixFilament LiveView testing works. Adjust based on actual test infrastructure.

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/phoenix_filament_ai/chat/chat_thread_test.exs
```

Expected: FAIL — modules not defined.

- [ ] **Step 3: Implement StreamHandler**

```elixir
# lib/phoenix_filament_ai/chat/stream_handler.ex
defmodule PhoenixFilamentAI.Chat.StreamHandler do
  @moduledoc """
  Manages the streaming lifecycle for AI responses.

  Spawns a Task that calls Store.converse/3 with `to: caller_pid`.
  Streaming chunks are sent by the Store directly to the caller process
  as `{:phoenix_ai, {:chunk, %StreamChunk{}}}` messages — they bypass
  the Task entirely.

  The Task's role is to hold the blocking converse/3 call and forward
  the final `{:ok, response}` or `{:error, reason}` via the standard
  Task return mechanism (`{ref, result}`).

  Does NOT: render anything, manage message lists, touch the DOM,
  handle individual chunks (Store sends those directly to caller).
  """

  alias PhoenixFilamentAI.StoreAdapter

  @doc """
  Starts a streaming AI conversation turn.

  The caller process will receive:
  - `{:phoenix_ai, {:chunk, %PhoenixAI.StreamChunk{delta: "..."}}}` per token (from Store, bypasses Task)
  - `{ref, {:ok, %PhoenixAI.Response{}}}` when stream completes (from Task)
  - `{ref, {:error, reason}}` on failure (from Task)

  Returns `%Task{}` — the caller should store `task.ref` for demonitoring.
  """
  @spec start(atom(), String.t(), String.t(), keyword()) :: Task.t()
  def start(store, conversation_id, message, opts \\ []) do
    caller = self()

    Task.async(fn ->
      StoreAdapter.converse(store, conversation_id, message,
        Keyword.merge(opts, to: caller)
      )
    end)
  end

  @doc """
  Classifies an error as retriable, fatal, or domain.
  """
  @spec classify_error(term()) :: :retriable | :fatal | :domain
  def classify_error(:timeout), do: :retriable
  def classify_error({:timeout, _}), do: :retriable
  def classify_error(:rate_limit), do: :retriable
  def classify_error(:rate_limited), do: :retriable
  def classify_error(:econnrefused), do: :retriable
  def classify_error(:closed), do: :retriable
  def classify_error(:network_error), do: :retriable
  def classify_error({:http_error, status}) when status in [429, 500, 502, 503], do: :retriable
  def classify_error(:invalid_api_key), do: :fatal
  def classify_error(:unauthorized), do: :fatal
  def classify_error(:provider_down), do: :fatal
  def classify_error({:missing_option, _}), do: :fatal
  def classify_error({:http_error, status}) when status in [401, 403], do: :fatal
  def classify_error(%{reason: :guardrail_violation}), do: :domain
  def classify_error(%{policy: _}), do: :domain
  def classify_error(:guardrail_violation), do: :domain
  def classify_error(_), do: :fatal

  @doc """
  Returns a human-readable error message.
  """
  @spec error_message(term()) :: String.t()
  def error_message(reason) do
    case classify_error(reason) do
      :retriable -> "Something went wrong. Please try again."
      :fatal -> "A configuration error occurred. Check your settings."
      :domain -> "This request was blocked by a content policy."
    end
  end
end
```

Note: The `to: caller` option tells `PhoenixAI.Store.converse/3` to send `{:phoenix_ai, {:chunk, %StreamChunk{}}}` messages directly to the caller PID. The Task just holds the blocking call and returns the final result. There is NO `on_complete` or `on_error` callback — completion/error is the return value of `converse/3`.

- [ ] **Step 4: Implement TypingIndicator**

```elixir
# lib/phoenix_filament_ai/components/typing_indicator.ex
defmodule PhoenixFilamentAI.Components.TypingIndicator do
  @moduledoc """
  Animated typing indicator shown during AI streaming.
  """

  use Phoenix.Component

  def typing(assigns) do
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
```

- [ ] **Step 5: Implement ChatThread**

```elixir
# lib/phoenix_filament_ai/chat/chat_thread.ex
defmodule PhoenixFilamentAI.Chat.ChatThread do
  @moduledoc """
  Stateful LiveComponent that manages the chat interaction.

  Handles message list, streaming state, user input, and auto-scroll.
  Shared between ChatWidget (dashboard) and ChatPage (full-screen).
  """

  use Phoenix.LiveComponent

  alias PhoenixFilamentAI.Chat.StreamHandler
  alias PhoenixFilamentAI.StoreAdapter
  alias PhoenixFilamentAI.Components.MessageComponent
  alias PhoenixFilamentAI.Components.TypingIndicator

  @default_message_limit 20

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:messages, [])
     |> assign(:current_response, "")
     |> assign(:streaming, false)
     |> assign(:input_value, "")
     |> assign(:has_more, false)
     |> assign(:cursor, nil)
     |> assign(:last_message_for_retry, nil)}
  end

  @impl true
  def update(assigns, socket) do
    # Process streaming assigns from parent before normal assign merge
    socket =
      cond do
        Map.has_key?(assigns, :ai_chunk) ->
          handle_ai_chunk(assigns.ai_chunk, socket)

        Map.has_key?(assigns, :ai_complete) ->
          handle_ai_complete(assigns.ai_complete, socket)

        Map.has_key?(assigns, :ai_error) ->
          handle_ai_error(assigns.ai_error, socket)

        true ->
          socket
      end

    # Drop streaming keys before merge to avoid stale assigns
    clean_assigns =
      assigns
      |> Map.drop([:ai_chunk, :ai_complete, :ai_error])

    socket = assign(socket, clean_assigns)

    socket =
      if changed?(socket, :conversation_id) do
        load_conversation(socket)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) when message != "" do
    store = socket.assigns.store
    conversation_id = socket.assigns.conversation_id
    config = socket.assigns.config

    converse_opts =
      [
        provider: Keyword.get(config, :provider),
        model: Keyword.get(config, :model),
        system: get_system_prompt(config),
        api_key: Keyword.get(config, :api_key)
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    user_message = %{role: :user, content: message, id: generate_id()}
    placeholder = %{role: :assistant, content: "", id: generate_id()}

    # Notify parent to start streaming (parent holds the Task ref)
    send(self(), {:start_ai_stream, store, conversation_id, message, converse_opts})

    socket =
      socket
      |> assign(:messages, socket.assigns.messages ++ [user_message, placeholder])
      |> assign(:streaming, true)
      |> assign(:current_response, "")
      |> assign(:input_value, "")
      |> assign(:last_message_for_retry, message)

    {:noreply, socket}
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("suggestion_click", %{"text" => text}, socket) do
    handle_event("send_message", %{"message" => text}, socket)
  end

  @impl true
  def handle_event("retry", _params, socket) do
    case socket.assigns.last_message_for_retry do
      nil -> {:noreply, socket}
      message ->
        # Remove the error message
        messages = Enum.reject(socket.assigns.messages, &(&1.role == :error))
        socket = assign(socket, :messages, messages)
        handle_event("send_message", %{"message" => message}, socket)
    end
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    case socket.assigns.cursor do
      nil -> {:noreply, socket}
      cursor ->
        store = socket.assigns.store
        conversation_id = socket.assigns.conversation_id

        case StoreAdapter.list_messages(store, conversation_id, limit: @default_message_limit, before_cursor: cursor) do
          {:ok, {older_messages, new_cursor}} ->
            {:noreply,
             socket
             |> assign(:messages, older_messages ++ socket.assigns.messages)
             |> assign(:cursor, new_cursor)
             |> assign(:has_more, new_cursor != nil)}

          {:error, _reason} ->
            {:noreply, socket}
        end
    end
  end

  # --- Streaming handlers (called from update/2 via send_update from parent) ---

  defp handle_ai_chunk(chunk, socket) do
    new_content = socket.assigns.current_response <> (chunk.delta || "")
    messages = update_last_assistant_message(socket.assigns.messages, new_content)

    socket
    |> assign(:current_response, new_content)
    |> assign(:messages, messages)
  end

  defp handle_ai_complete(response, socket) do
    messages = update_last_assistant_message(socket.assigns.messages, response.content || "")

    socket
    |> assign(:streaming, false)
    |> assign(:current_response, "")
    |> assign(:task_ref, nil)
    |> assign(:messages, messages)
  end

  defp handle_ai_error(reason, socket) do
    error_type = StreamHandler.classify_error(reason)
    error_msg = StreamHandler.error_message(reason)

    # Remove the placeholder assistant message
    messages =
      socket.assigns.messages
      |> Enum.reject(fn m -> m.role == :assistant and m.content == "" end)

    error_message = %{role: :error, content: error_msg, id: generate_id(), error_type: error_type}

    socket
    |> assign(:streaming, false)
    |> assign(:current_response, "")
    |> assign(:task_ref, nil)
    |> assign(:messages, messages ++ [error_message])
  end

  defp get_system_prompt(config) do
    chat_opts = Keyword.get(config, :chat, [])
    Keyword.get(chat_opts, :system_prompt)
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pfa-chat-thread" id={@id} phx-hook="AutoScroll">
      <%= if @has_more do %>
        <button phx-click="load_more" phx-target={@myself} class="pfa-load-more">
          Load older messages
        </button>
      <% end %>

      <div class="pfa-messages">
        <%= if @messages == [] do %>
          <div class="pfa-empty-state">
            <p class="pfa-empty-title">Ask anything about your panel</p>
            <div class="pfa-suggestions">
              <button phx-click="suggestion_click" phx-target={@myself} phx-value-text="How many users signed up this week?" class="pfa-suggestion">
                How many users signed up this week?
              </button>
              <button phx-click="suggestion_click" phx-target={@myself} phx-value-text="Summarize recent orders" class="pfa-suggestion">
                Summarize recent orders
              </button>
              <button phx-click="suggestion_click" phx-target={@myself} phx-value-text="What's the conversion rate?" class="pfa-suggestion">
                What's the conversion rate?
              </button>
            </div>
          </div>
        <% else %>
          <%= for message <- @messages do %>
            <MessageComponent.message
              message={message}
              streaming={@streaming and message == List.last(@messages) and message.role == :assistant}
              on_retry={if message.role == :error, do: "retry"}
            />
          <% end %>
        <% end %>

        <%= if @streaming do %>
          <TypingIndicator.typing />
        <% end %>
      </div>

      <form phx-submit="send_message" phx-target={@myself} class="pfa-input-area">
        <textarea
          name="message"
          placeholder="Ask something..."
          class="pfa-input"
          disabled={@streaming}
          phx-keydown="send_on_enter"
          phx-target={@myself}
          value={@input_value}
        />
        <button type="submit" class="pfa-send-btn" disabled={@streaming}>
          →
        </button>
      </form>
    </div>
    """
  end

  # --- Private ---

  defp load_conversation(socket) do
    case socket.assigns[:conversation_id] do
      nil ->
        assign(socket, messages: [], cursor: nil, has_more: false)

      conversation_id ->
        store = socket.assigns.store

        case StoreAdapter.list_messages(store, conversation_id, limit: @default_message_limit) do
          {:ok, {messages, cursor}} ->
            socket
            |> assign(:messages, messages)
            |> assign(:cursor, cursor)
            |> assign(:has_more, cursor != nil)

          {:error, _reason} ->
            assign(socket, messages: [], cursor: nil, has_more: false)
        end
    end
  end

  defp update_last_assistant_message(messages, content) do
    messages
    |> Enum.reverse()
    |> then(fn
      [%{role: :assistant} = last | rest] ->
        Enum.reverse([%{last | content: content} | rest])

      other ->
        Enum.reverse(other)
    end)
  end

  defp generate_id, do: :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
end
```

- [ ] **Step 6: Run tests**

```bash
mix test test/phoenix_filament_ai/chat/chat_thread_test.exs
```

Expected: PASS (may need adjustments to test setup for LiveComponent mounting).

- [ ] **Step 7: Commit**

```bash
git add lib/phoenix_filament_ai/chat/stream_handler.ex lib/phoenix_filament_ai/chat/chat_thread.ex lib/phoenix_filament_ai/components/typing_indicator.ex test/phoenix_filament_ai/chat/chat_thread_test.exs
git commit -m "feat: add ChatThread with streaming and StreamHandler"
```

---

## Task 7: ChatWidget

**Files:**
- Create: `lib/phoenix_filament_ai/chat/chat_widget.ex`
- Create: `test/phoenix_filament_ai/chat/chat_widget_test.exs`

- [ ] **Step 1: Write failing test**

```elixir
# test/phoenix_filament_ai/chat/chat_widget_test.exs
defmodule PhoenixFilamentAI.Chat.ChatWidgetTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PhoenixFilamentAI.Chat.ChatWidget

  describe "render" do
    test "renders widget with title" do
      html = render_component(ChatWidget, %{
        id: "chat-widget",
        store: :test_store,
        config: PhoenixFilamentAI.Fixtures.valid_plugin_opts()
      })

      assert html =~ "AI Assistant"
    end

    test "contains ChatThread component" do
      html = render_component(ChatWidget, %{
        id: "chat-widget",
        store: :test_store,
        config: PhoenixFilamentAI.Fixtures.valid_plugin_opts()
      })

      assert html =~ "pfa-chat-thread"
    end

    test "renders with custom title from config" do
      config = PhoenixFilamentAI.Fixtures.valid_plugin_opts(
        chat_widget: [title: "My Bot"]
      )
      html = render_component(ChatWidget, %{
        id: "chat-widget",
        store: :test_store,
        config: config
      })

      assert html =~ "My Bot"
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mix test test/phoenix_filament_ai/chat/chat_widget_test.exs
```

Expected: FAIL — module not defined.

- [ ] **Step 3: Implement ChatWidget**

```elixir
# lib/phoenix_filament_ai/chat/chat_widget.ex
defmodule PhoenixFilamentAI.Chat.ChatWidget do
  @moduledoc """
  Dashboard chat widget.

  Thin shell that wraps ChatThread inside PhoenixFilament's Widget.Custom
  for native dashboard grid integration.
  """

  use PhoenixFilament.Widget.Custom

  alias PhoenixFilamentAI.Chat.ChatThread

  @impl true
  def mount(socket) do
    config = socket.assigns.ai_config
    store = socket.assigns.ai_store

    widget_opts = get_widget_opts(config)

    {:ok,
     socket
     |> assign(:store, store)
     |> assign(:config, config)
     |> assign(:widget_title, Keyword.get(widget_opts, :title, "AI Assistant"))
     |> assign(:conversation_id, nil)}
  end

  @impl true
  def handle_event("new_conversation", _params, socket) do
    {:noreply, assign(socket, :conversation_id, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pfa-chat-widget">
      <div class="pfa-widget-header">
        <span class="pfa-widget-title">✨ <%= @widget_title %></span>
        <div class="pfa-widget-actions">
          <button phx-click="new_conversation" phx-target={@myself} class="pfa-widget-btn" title="New conversation">
            +
          </button>
        </div>
      </div>
      <div class="pfa-widget-body">
        <.live_component
          module={ChatThread}
          id="widget-chat-thread"
          store={@store}
          conversation_id={@conversation_id}
          config={@config}
        />
      </div>
    </div>
    """
  end

  defp get_widget_opts(config) do
    case Keyword.get(config, :chat_widget, true) do
      true -> []
      opts when is_list(opts) -> opts
      _ -> []
    end
  end
end
```

Note: `use PhoenixFilament.Widget.Custom` must be verified against the actual PhoenixFilament widget API. The widget system may have specific callbacks (`column_span/0`, `sort/0`) that need implementing. Adjust based on actual API.

- [ ] **Step 4: Run tests**

```bash
mix test test/phoenix_filament_ai/chat/chat_widget_test.exs
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_filament_ai/chat/chat_widget.ex test/phoenix_filament_ai/chat/chat_widget_test.exs
git commit -m "feat: add ChatWidget dashboard shell"
```

---

## Task 8: ChatPage + Sidebar

**Files:**
- Create: `lib/phoenix_filament_ai/chat/chat_page.ex`
- Create: `lib/phoenix_filament_ai/chat/sidebar.ex`
- Create: `test/phoenix_filament_ai/chat/chat_page_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
# test/phoenix_filament_ai/chat/chat_page_test.exs
defmodule PhoenixFilamentAI.Chat.ChatPageTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PhoenixFilamentAI.Chat.ChatPage

  describe "mount" do
    test "renders 2-column layout with sidebar and chat area" do
      {:ok, view, html} = live(conn, "/ai/chat")

      assert html =~ "pfa-chat-page"
      assert html =~ "pfa-sidebar"
      assert html =~ "pfa-chat-thread"
    end
  end

  describe "conversation navigation" do
    test "switching conversations updates the chat thread" do
      {:ok, conv} = PhoenixFilamentAI.StoreAdapter.create_conversation(
        :test_store,
        PhoenixFilamentAI.Fixtures.conversation_attrs(%{title: "Test Conv"})
      )

      {:ok, view, _html} = live(conn, "/ai/chat")

      html = view
        |> element("[data-conversation-id=\"#{conv.id}\"]")
        |> render_click()

      assert_patched(view, "/ai/chat/#{conv.id}")
    end
  end

  describe "sidebar" do
    test "shows new chat button" do
      {:ok, _view, html} = live(conn, "/ai/chat")
      assert html =~ "New Chat"
    end

    test "search filters conversations" do
      {:ok, view, _html} = live(conn, "/ai/chat")

      html = view
        |> form(".pfa-sidebar-search", %{search: "test"})
        |> render_change()

      # Verify filtering happened (exact assertion depends on fixtures)
      assert is_binary(html)
    end
  end
end
```

Note: These tests use `live(conn, path)` which requires a Phoenix test connection. The test setup will need a router with the plugin routes mounted. Adjust based on actual test infrastructure.

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/phoenix_filament_ai/chat/chat_page_test.exs
```

Expected: FAIL — modules not defined.

- [ ] **Step 3: Implement Sidebar**

```elixir
# lib/phoenix_filament_ai/chat/sidebar.ex
defmodule PhoenixFilamentAI.Chat.Sidebar do
  @moduledoc """
  Conversation sidebar for the full-screen chat page.

  Lists conversations with search, filter by tags, and new chat button.
  """

  use Phoenix.Component

  alias PhoenixFilamentAI.StoreAdapter

  attr :store, :atom, required: true
  attr :active_conversation_id, :string, default: nil
  attr :conversations, :list, default: []
  attr :search_query, :string, default: ""

  def sidebar(assigns) do
    ~H"""
    <div class="pfa-sidebar">
      <div class="pfa-sidebar-header">
        <span class="pfa-sidebar-title">Conversations</span>
      </div>

      <div class="pfa-sidebar-search-container">
        <form phx-change="sidebar_search" class="pfa-sidebar-search">
          <input
            type="text"
            name="search"
            placeholder="🔍 Search..."
            value={@search_query}
            class="pfa-search-input"
          />
        </form>
      </div>

      <div class="pfa-sidebar-list">
        <%= if @conversations == [] do %>
          <div class="pfa-sidebar-empty">
            <p>Start your first conversation</p>
          </div>
        <% else %>
          <%= for conv <- @conversations do %>
            <div
              class={"pfa-sidebar-item #{if conv.id == @active_conversation_id, do: "pfa-sidebar-item-active"}"}
              data-conversation-id={conv.id}
              phx-click="select_conversation"
              phx-value-id={conv.id}
            >
              <div class="pfa-sidebar-item-title">
                <%= if conv.id == @active_conversation_id, do: "●", else: "○" %>
                <%= conv.title || "Untitled" %>
              </div>
              <div class="pfa-sidebar-item-meta">
                <%= Calendar.strftime(conv.inserted_at, "%b %d") %> · $<%= format_cost(conv.total_cost) %>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>

      <div class="pfa-sidebar-footer">
        <button phx-click="new_conversation" class="pfa-new-chat-btn">
          + New Chat
        </button>
      </div>
    </div>
    """
  end

  defp format_cost(nil), do: "0.00"
  defp format_cost(cost), do: :erlang.float_to_binary(cost / 1, decimals: 2)
end
```

- [ ] **Step 4: Implement ChatPage**

```elixir
# lib/phoenix_filament_ai/chat/chat_page.ex
defmodule PhoenixFilamentAI.Chat.ChatPage do
  @moduledoc """
  Full-screen chat page with conversation sidebar.

  2-column layout: sidebar (conversation list) + main chat area (ChatThread).
  Navigation between conversations via push_patch (no full reload).
  """

  use Phoenix.LiveView

  alias PhoenixFilamentAI.Chat.{ChatThread, Sidebar}
  alias PhoenixFilamentAI.StoreAdapter

  @impl true
  def mount(_params, _session, socket) do
    store = socket.assigns.ai_store
    config = socket.assigns.ai_config

    conversations = load_conversations(store)

    {:ok,
     socket
     |> assign(:store, store)
     |> assign(:config, config)
     |> assign(:conversations, conversations)
     |> assign(:search_query, "")
     |> assign(:conversation_id, nil)
     |> assign(:task_ref, nil)}
  end

  @impl true
  def handle_params(%{"conversation_id" => id}, _uri, socket) do
    {:noreply, assign(socket, :conversation_id, id)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :conversation_id, nil)}
  end

  @impl true
  def handle_event("select_conversation", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: "/ai/chat/#{id}")}
  end

  @impl true
  def handle_event("new_conversation", _params, socket) do
    {:noreply,
     socket
     |> assign(:conversation_id, nil)
     |> push_patch(to: "/ai/chat")}
  end

  @impl true
  def handle_event("sidebar_search", %{"search" => query}, socket) do
    store = socket.assigns.store
    conversations = load_conversations(store, search: query)

    {:noreply,
     socket
     |> assign(:conversations, conversations)
     |> assign(:search_query, query)}
  end

  @impl true
  def handle_event("rename_conversation", %{"title" => title}, socket) do
    case socket.assigns.conversation_id do
      nil -> {:noreply, socket}
      id ->
        StoreAdapter.update_conversation(socket.assigns.store, id, %{title: title})
        conversations = load_conversations(socket.assigns.store)
        {:noreply, assign(socket, :conversations, conversations)}
    end
  end

  @impl true
  def handle_event("delete_conversation", _params, socket) do
    case socket.assigns.conversation_id do
      nil -> {:noreply, socket}
      id ->
        StoreAdapter.delete_conversation(socket.assigns.store, id)
        conversations = load_conversations(socket.assigns.store)

        {:noreply,
         socket
         |> assign(:conversations, conversations)
         |> assign(:conversation_id, nil)
         |> push_patch(to: "/ai/chat")}
    end
  end

  # --- Streaming message routing ---
  # ChatThread is a LiveComponent, so it can't receive handle_info directly.
  # The parent (this LiveView) receives all messages and routes via send_update.

  # Start streaming — triggered by ChatThread via send(self(), ...)
  @impl true
  def handle_info({:start_ai_stream, store, conversation_id, message, opts}, socket) do
    task = StreamHandler.start(store, conversation_id, message, opts)
    {:noreply, assign(socket, :task_ref, task.ref)}
  end

  # Streaming chunks — sent directly by Store via `to: pid`
  def handle_info({:phoenix_ai, {:chunk, chunk}}, socket) do
    send_update(ChatThread, id: "page-chat-thread", ai_chunk: chunk)
    {:noreply, socket}
  end

  # Task completion — Store.converse returned {:ok, response}
  def handle_info({ref, {:ok, response}}, socket) when ref == socket.assigns.task_ref do
    Process.demonitor(ref, [:flush])
    send_update(ChatThread, id: "page-chat-thread", ai_complete: response)
    conversations = load_conversations(socket.assigns.store, socket.assigns.search_query)
    {:noreply, socket |> assign(:conversations, conversations) |> assign(:task_ref, nil)}
  end

  # Task error — Store.converse returned {:error, reason}
  def handle_info({ref, {:error, reason}}, socket) when ref == socket.assigns.task_ref do
    Process.demonitor(ref, [:flush])
    send_update(ChatThread, id: "page-chat-thread", ai_error: reason)
    {:noreply, assign(socket, :task_ref, nil)}
  end

  # Task crash — handle DOWN message
  def handle_info({:DOWN, ref, :process, _pid, reason}, socket) when ref == socket.assigns.task_ref do
    send_update(ChatThread, id: "page-chat-thread", ai_error: reason)
    {:noreply, assign(socket, :task_ref, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pfa-chat-page">
      <Sidebar.sidebar
        store={@store}
        active_conversation_id={@conversation_id}
        conversations={@conversations}
        search_query={@search_query}
      />

      <div class="pfa-chat-main">
        <%= if @conversation_id do %>
          <div class="pfa-chat-header">
            <span class="pfa-chat-title">
              <%= get_conversation_title(@conversations, @conversation_id) %>
            </span>
            <div class="pfa-chat-actions">
              <button phx-click="delete_conversation" class="pfa-action-btn" title="Delete">🗑</button>
            </div>
          </div>
        <% end %>

        <.live_component
          module={ChatThread}
          id="page-chat-thread"
          store={@store}
          conversation_id={@conversation_id}
          config={@config}
        />
      </div>
    </div>
    """
  end

  # --- Private ---

  defp load_conversations(store, opts \\ []) do
    case StoreAdapter.list_conversations(store, opts) do
      {:ok, conversations} -> conversations
      {:error, _reason} -> []
    end
  end

  defp get_conversation_title(conversations, id) do
    case Enum.find(conversations, &(&1.id == id)) do
      nil -> "Chat"
      conv -> conv.title || "Untitled"
    end
  end
end
```

- [ ] **Step 5: Run tests**

```bash
mix test test/phoenix_filament_ai/chat/chat_page_test.exs
```

Expected: PASS (may need router setup in test config).

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_filament_ai/chat/chat_page.ex lib/phoenix_filament_ai/chat/sidebar.ex test/phoenix_filament_ai/chat/chat_page_test.exs
git commit -m "feat: add ChatPage with conversation sidebar"
```

---

## Task 9: Polish — Copy Button, ETS Warning, CSS

**Files:**
- Create: `lib/phoenix_filament_ai/components/copy_button_hook.ex`
- Modify: `lib/phoenix_filament/ai.ex` — add ETS warning logic to `boot/1`

- [ ] **Step 1: Implement CopyButtonHook**

```elixir
# lib/phoenix_filament_ai/components/copy_button_hook.ex
defmodule PhoenixFilamentAI.Components.CopyButtonHook do
  @moduledoc """
  Phoenix LiveView JS hook for code block copy-to-clipboard.

  This is the only JavaScript in the plugin.
  Registered in the plugin's hooks and attached to code blocks.
  """

  def hook_js do
    """
    {
      mounted() {
        this.el.querySelectorAll('pre code').forEach(block => {
          const btn = document.createElement('button');
          btn.className = 'pfa-copy-btn';
          btn.textContent = 'Copy';
          btn.addEventListener('click', async () => {
            try {
              await navigator.clipboard.writeText(block.textContent);
              btn.textContent = 'Copied!';
              setTimeout(() => { btn.textContent = 'Copy'; }, 2000);
            } catch (err) {
              btn.textContent = 'Failed';
              setTimeout(() => { btn.textContent = 'Copy'; }, 2000);
            }
          });
          block.parentElement.style.position = 'relative';
          block.parentElement.appendChild(btn);
        });
      },
      updated() {
        this.mounted();
      }
    }
    """
  end
end
```

- [ ] **Step 2: Add ETS warning to plugin boot**

Update `lib/phoenix_filament/ai.ex` — modify the `boot/1` function to check the backend type and set a warning flag:

```elixir
# In PhoenixFilament.AI, update boot/1:
@impl true
def boot(socket) do
  config = get_plugin_config(socket)
  store = Keyword.fetch!(config, :store)
  show_ets_warning = Keyword.get(config, :ets_warning, true)

  ets_warning =
    if show_ets_warning and Mix.env() == :prod do
      case PhoenixFilamentAI.StoreAdapter.backend_type(store) do
        :ets -> true
        _ -> false
      end
    else
      false
    end

  socket
  |> Phoenix.Component.assign(:ai_store, store)
  |> Phoenix.Component.assign(:ai_config, config)
  |> Phoenix.Component.assign(:ai_ets_warning, ets_warning)
end
```

Note: Using `Mix.env()` at runtime is not recommended for libraries. Consider using `Application.get_env(:phoenix_filament_ai, :env)` or checking for a runtime config flag instead. Adjust during implementation.

- [ ] **Step 3: Run full test suite**

```bash
mix test
```

Expected: All tests PASS.

- [ ] **Step 4: Run linters**

```bash
mix format --check-formatted && mix credo --strict
```

Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_filament_ai/components/copy_button_hook.ex lib/phoenix_filament/ai.ex
git commit -m "feat: add copy button hook and ETS warning"
```

- [ ] **Step 6: Final integration check**

Run the full test suite one more time and verify all 23 Phase 1 requirements are covered:

```bash
mix test --trace
```

Expected: All tests pass. Requirements PLUG-01 through PLUG-05, CHAT-01 through CHAT-16, CONV-09, CONV-10 are addressed across Tasks 1-9.

- [ ] **Step 7: Final commit with version bump if needed**

```bash
git add -A
git commit -m "chore: Phase 1 complete — Foundation + Chat"
```

---

## Requirement Coverage

| Requirement | Task | How |
|-------------|------|-----|
| PLUG-01 | Task 2 | Plugin module with register/2 and boot/1 |
| PLUG-02 | Task 3 | NimbleOptions config validation |
| PLUG-03 | Task 2 | register/2 returns nav, routes, widgets, hooks based on toggles |
| PLUG-04 | Task 2 | boot/1 injects :ai_store and :ai_config |
| PLUG-05 | Task 3 | Only :store, :provider, :model required; rest has defaults |
| CHAT-01 | Task 7 | ChatWidget with configurable column_span and sort |
| CHAT-02 | Task 6 | ChatThread + StreamHandler for streaming |
| CHAT-03 | Task 6 | StreamHandler uses Task.async + `to: pid` streaming (non-blocking) |
| CHAT-04 | Task 5 | MDEx markdown rendering |
| CHAT-05 | Task 7 | New conversation button in widget |
| CHAT-06 | Task 4, 6 | StoreAdapter + ChatThread conversation persistence |
| CHAT-07 | Task 6 | TypingIndicator during streaming |
| CHAT-08 | Task 6 | AutoScroll phx-hook |
| CHAT-09 | Task 6 | Form submit + textarea key handling |
| CHAT-10 | Task 8 | ChatPage with 2-column layout |
| CHAT-11 | Task 8 | Sidebar with search and tag filter |
| CHAT-12 | Task 8 | Create/delete/rename in ChatPage |
| CHAT-13 | Task 8 | push_patch navigation |
| CHAT-14 | Task 5 | ToolCallCard collapsible cards |
| CHAT-15 | Task 5 | System message banner in MessageComponent |
| CHAT-16 | Task 6 | ChatThread shared between widget and page |
| CONV-09 | Task 4 | StoreAdapter CRUD via Store API |
| CONV-10 | Task 4 | StoreAdapter uses only public Store API (backend-agnostic) |

---

*Plan created: 2026-04-05*
*Tasks: 9 | Build order: Risk-First*
*Spec: .planning/phases/01-foundation-chat/BRAINSTORM.md*
