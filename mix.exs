defmodule WebRTCLive.MixProject do
  use Mix.Project

  def project do
    [
      app: :webrtc_live,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: [
        {:phoenix, "~> 1.8.0"},
        {:bandit, "~> 1.0"},
        {:jason, "~> 1.4"},
        {:ex_webrtc, "~> 0.17.0"}
      ]
    ]
  end

  def application do
    [mod: {WebRTCLive.Application, []}, extra_applications: [:logger]]
  end
end
