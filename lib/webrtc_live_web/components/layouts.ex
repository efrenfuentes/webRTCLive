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
          :root { color-scheme: dark; font: 16px/1.6 system-ui, sans-serif; background: #101619; color: #edf5f3; }
          * { box-sizing: border-box; }
          body { max-width: 760px; margin: 6vh auto; padding: 24px; }
          nav { display: flex; gap: 1rem; align-items: center; flex-wrap: wrap; }
          nav span { overflow-wrap: anywhere; min-width: 0; }
          h1 { font-size: clamp(32px, 7vw, 48px); line-height: 1.15; letter-spacing: -.04em; overflow-wrap: anywhere; }
          p { color: #b7c7c2; }
          input, select, button { font: inherit; padding: 10px 14px; border: 1px solid #53645e; border-radius: 8px; background: #1c2924; color: inherit; max-width: 100%; }
          input:not([type=hidden]), select { width: 100%; }
          label { display: block; } button { cursor: pointer; background: #8fe5cb; color: #11251d; font-weight: 700; }
          button[type=button], nav button { background: #1c2924; color: #edf5f3; }
          button:disabled { opacity: .4; cursor: default; }
          :focus-visible { outline: 2px solid #75dcc3; outline-offset: 3px; }
          form { margin: 1rem 0; padding: 24px; border: 1px solid #35433f; border-radius: 16px; display: grid; gap: 14px; }
          nav form { padding: 0; border: 0; margin: 0; }
          [role=alert] { color: #ffb4ab; } a { color: #75dcc3; }
          [role=status], #status { color: #8fe5cb; overflow-wrap: anywhere; }
          audio { width: 100%; margin: 10px 0; }
          small { color: #a4b7af; }
          #participants { display: grid; gap: 12px; margin-bottom: 20px; }
          #participants section, .room-card { border: 1px solid #35433f; border-radius: 12px; padding: 16px; }
          #participants strong, #participants small { display: block; }
          .room-list { list-style: none; padding: 0; display: grid; gap: 12px; }
          .room-card { display: flex; flex-wrap: wrap; gap: 16px; align-items: center; justify-content: space-between; }
          .room-card a { overflow-wrap: anywhere; }
          .danger { color: #ffb4ab; }
          button.danger { background: #4b2426; border-color: #a66668; }
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
