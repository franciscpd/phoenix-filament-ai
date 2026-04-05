defmodule PhoenixFilament.AI do
  @moduledoc """
  PhoenixFilament plugin for AI capabilities.

  Registers AI-related navigation, routes, widgets, and hooks into a
  PhoenixFilament panel based on the provided configuration options.

  ## Usage

      defmodule MyApp.Admin do
        use PhoenixFilament.Panel, path: "/admin"

        plugins do
          plugin PhoenixFilament.AI,
            store: MyApp.AIStore,
            provider: :openai,
            model: "gpt-4o"
        end
      end

  ## Options

  See `PhoenixFilamentAI.Config` for all available options.
  """

  use PhoenixFilament.Plugin

  alias PhoenixFilamentAI.Config

  @impl true
  def register(_panel, opts) do
    config = Config.validate!(opts)

    %{
      nav_items: build_nav_items(config),
      routes: build_routes(config),
      widgets: build_widgets(config),
      hooks: build_hooks(config)
    }
  end

  @impl true
  def boot(socket) do
    config = socket.assigns[:phoenix_filament_ai]

    socket
    |> Phoenix.Component.assign(:ai_store, config[:store])
    |> Phoenix.Component.assign(:ai_config, config)
  end

  # -- Private helpers --

  defp build_nav_items(config) do
    nav_group = config[:nav_group]
    icon = config[:nav_icon]

    []
    |> maybe_add_nav(config, :chat_page, "Chat", icon, nav_group)
    |> maybe_add_nav(config, :conversations, "Conversations", icon, nav_group)
    |> maybe_add_nav(config, :cost_dashboard, "Costs", icon, nav_group)
    |> maybe_add_nav(config, :event_log, "Event Log", icon, nav_group)
  end

  defp maybe_add_nav(items, config, feature, label, icon, nav_group) do
    if Config.feature_enabled?(config, feature) do
      items ++
        [nav_item(label, path: "/ai/#{path_segment(feature)}", icon: icon, nav_group: nav_group)]
    else
      items
    end
  end

  defp path_segment(:chat_page), do: "chat"
  defp path_segment(:conversations), do: "conversations"
  defp path_segment(:cost_dashboard), do: "costs"
  defp path_segment(:event_log), do: "events"

  defp build_routes(config) do
    []
    |> maybe_add_route(config, :chat_page, "/ai/chat", PhoenixFilamentAI.ChatLive, :index)
    |> maybe_add_route(
      config,
      :conversations,
      "/ai/conversations",
      PhoenixFilamentAI.ConversationsLive,
      :index
    )
    |> maybe_add_route(config, :cost_dashboard, "/ai/costs", PhoenixFilamentAI.CostsLive, :index)
    |> maybe_add_route(config, :event_log, "/ai/events", PhoenixFilamentAI.EventsLive, :index)
  end

  defp maybe_add_route(routes, config, feature, path, live_view, action) do
    if Config.feature_enabled?(config, feature) do
      routes ++ [route(path, live_view, action)]
    else
      routes
    end
  end

  defp build_widgets(config) do
    if Config.feature_enabled?(config, :chat_widget) do
      {column_span, sort} = widget_opts(config[:chat_widget])

      [
        %{
          module: PhoenixFilamentAI.ChatWidget,
          sort: sort,
          column_span: column_span
        }
      ]
    else
      []
    end
  end

  defp widget_opts(true), do: {6, 100}

  defp widget_opts(opts) when is_list(opts) do
    {opts[:column_span] || 6, opts[:sort] || 100}
  end

  defp build_hooks(_config) do
    []
  end
end
