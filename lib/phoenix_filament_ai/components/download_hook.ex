defmodule PhoenixFilamentAI.Components.DownloadHook do
  @moduledoc """
  JavaScript hook for triggering file downloads from LiveView events.

  Listens for `pfa:download` events pushed from the server via `push_event/3`
  and triggers a browser file download using a Blob URL. The content is
  Base64-encoded on the server to survive JSON serialization.

  ## Usage

  Include the hook in your LiveSocket configuration:

      import {Socket} from "phoenix"
      import {LiveSocket} from "phoenix_live_view"

      const Hooks = {}
      Hooks.PfaDownload = #{inspect("// paste hook_js() output here")}

      let liveSocket = new LiveSocket("/live", Socket, {
        hooks: Hooks
      })

  Attach to any element that pushes download events:

      <div id="my-view" phx-hook="PfaDownload">
  """

  @hook_js ~S"""
  {
    mounted() {
      this.handleEvent("pfa:download", ({content, filename, content_type}) => {
        const bytes = atob(content)
        const array = new Uint8Array(bytes.length)
        for (let i = 0; i < bytes.length; i++) { array[i] = bytes.charCodeAt(i) }
        const blob = new Blob([array], {type: content_type})
        const url = URL.createObjectURL(blob)
        const a = document.createElement("a")
        a.href = url
        a.download = filename
        document.body.appendChild(a)
        a.click()
        document.body.removeChild(a)
        URL.revokeObjectURL(url)
      })
    }
  }
  """

  @doc "Returns the PfaDownload hook JavaScript source as a string."
  @spec hook_js() :: String.t()
  def hook_js, do: @hook_js
end
