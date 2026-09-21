defmodule WebRTCLiveWeb.Layouts do
  use WebRTCLiveWeb, :html

  attr(:flash, :map, default: %{})
  attr(:current_scope, :any, default: nil)
  slot(:inner_block, required: true)

  def app(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="referrer" content="no-referrer" />
        <title>WebRTCLive</title>
        <style>
          body { font: 16px system-ui; max-width: 760px; margin: 3rem auto; padding: 0 1rem; color: #182235; background: #f5f7fb; }
          nav { display: flex; gap: 1rem; align-items: center; flex-wrap: wrap; }
          input, select, button { font: inherit; padding: .7rem; margin: .4rem 0 1rem; border: 1px solid #aab5c4; border-radius: 6px; }
          label { display: block; } button { cursor: pointer; background: #163965; color: white; }
          form { margin: 1rem 0; } [role=alert] { color: #9a1727; } a { color: #164d91; }
        </style>
      </head>
      <body>
        <nav>
          <a href="/">WebRTCLive</a>
          <span :if={@current_scope}>{@current_scope.user.email}</span>
          <a :if={@current_scope} href="/users/settings">Settings</a>
          <.form :if={@current_scope} for={%{}} action="/users/log-out" method="delete"><button>Log out</button></.form>
        </nav>
        <p :for={{kind, message} <- @flash} role={if kind == "error", do: "alert", else: "status"}>{message}</p>
        <main>{render_slot(@inner_block)}</main>
      </body>
    </html>
    """
  end
end
