defmodule PhoenixFilamentAI.Components.CopyButtonHook do
  @moduledoc """
  JavaScript hook for adding copy-to-clipboard buttons to code blocks.

  This is the only JavaScript in the plugin. The hook finds all `pre code`
  blocks in the element and adds a "Copy" button to each one. Clicking the
  button copies the code text to the clipboard and shows a "Copied!"
  confirmation for 2 seconds.

  ## Usage

  Include the hook in your LiveSocket configuration:

      import {Socket} from "phoenix"
      import {LiveSocket} from "phoenix_live_view"

      const Hooks = {}
      Hooks.AICopyButton = #{inspect("// paste hook_js() output here")}

      let liveSocket = new LiveSocket("/live", Socket, {
        hooks: Hooks
      })

  Or use `hook_js/0` to get the JavaScript source as a string.
  """

  @hook_js ~S"""
  {
    mounted() {
      this._addCopyButtons()
    },
    updated() {
      this._addCopyButtons()
    },
    _addCopyButtons() {
      this.el.querySelectorAll("pre code").forEach((codeBlock) => {
        const pre = codeBlock.parentElement
        if (pre.querySelector("[data-copy-button]")) return

        pre.style.position = "relative"

        const button = document.createElement("button")
        button.setAttribute("data-copy-button", "true")
        button.textContent = "Copy"
        button.type = "button"
        button.style.cssText = "position:absolute;top:0.5rem;right:0.5rem;padding:0.25rem 0.5rem;font-size:0.75rem;border-radius:0.25rem;border:1px solid rgba(255,255,255,0.2);background:rgba(0,0,0,0.3);color:#e5e7eb;cursor:pointer;"

        button.addEventListener("click", () => {
          const text = codeBlock.textContent
          navigator.clipboard.writeText(text).then(() => {
            button.textContent = "Copied!"
            setTimeout(() => { button.textContent = "Copy" }, 2000)
          })
        })

        pre.appendChild(button)
      })
    }
  }
  """

  @doc "Returns the AICopyButton hook JavaScript source as a string."
  @spec hook_js() :: String.t()
  def hook_js, do: @hook_js
end
