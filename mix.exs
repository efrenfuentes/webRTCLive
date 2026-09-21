defmodule WebRTCLive.MixProject do
  use Mix.Project

  def project do
    [
      app: :webrtc_live,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      deps: [
        {:phoenix, "~> 1.8.0"},
        {:bandit, "~> 1.0"},
        {:jason, "~> 1.4"},
        {:ecto_sql, "~> 3.13"},
        {:phoenix_ecto, "~> 4.6"},
        {:postgrex, ">= 0.0.0"},
        {:phoenix_html, "~> 4.0"},
        {:phoenix_live_view, "~> 1.1"},
        {:swoosh, "~> 1.19"},
        {:req, "~> 0.7"},
        {:bcrypt_elixir, "~> 3.0"},
        {:ex_webrtc, "~> 0.17.0"}
      ]
    ]
  end

  def application do
    [mod: {WebRTCLive.Application, []}, extra_applications: [:logger]]
  end
end
