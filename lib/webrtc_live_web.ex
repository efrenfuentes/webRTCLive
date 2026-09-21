defmodule WebRTCLiveWeb do
  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]
      import Plug.Conn
      unquote(verified_routes())
    end
  end

  def html do
    quote do
      use Phoenix.Component
      import WebRTCLiveWeb.CoreComponents
      alias Phoenix.LiveView.JS
      alias WebRTCLiveWeb.Layouts
      unquote(verified_routes())
    end
  end

  def router do
    quote do
      use Phoenix.Router, helpers: false
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: WebRTCLive.Endpoint,
        router: WebRTCLiveWeb.Router,
        statics: []
    end
  end

  defmacro __using__(which), do: apply(__MODULE__, which, [])
end
