defmodule WebRTCLiveWeb.Router do
  use WebRTCLiveWeb, :router

  import WebRTCLiveWeb.UserAuth

  pipeline :browser do
    plug(:accepts, ["html", "json"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:protect_from_forgery)

    plug(:put_secure_browser_headers, %{
      "cache-control" => "no-store",
      "referrer-policy" => "no-referrer"
    })

    plug(:fetch_current_scope_for_user)
    plug(WebRTCLiveWeb.RequestLimits)
  end

  ## Authentication routes

  scope "/", WebRTCLiveWeb do
    pipe_through([:browser, :require_authenticated_user])

    get("/", RoomController, :index)
    post("/rooms", RoomController, :create)
    post("/rooms/:slug/invitations", RoomController, :invite)
    get("/rooms/:slug", RoomController, :show)
    post("/rooms/:slug/join", RoomController, :join)
    get("/users/settings", UserSettingsController, :edit)
    put("/users/settings", UserSettingsController, :update)
    get("/users/settings/confirm-email/:token", UserSettingsController, :confirm_email)
  end

  scope "/", WebRTCLiveWeb do
    pipe_through([:browser])

    get("/users/log-in", UserSessionController, :new)
    get("/users/log-in/:token", UserSessionController, :confirm)
    post("/users/log-in", UserSessionController, :create)
    delete("/users/log-out", UserSessionController, :delete)
  end

  if Application.compile_env(:webrtc_live, :demo_tokens, false) do
    forward("/dev/mailbox", Plug.Swoosh.MailboxPreview)
  end

  forward("/", WebRTCLive.Router)
end
