import Config

config :webrtc_live, WebRTCLive.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: 4000],
  server: true,
  secret_key_base: String.duplicate("local-development-only-", 4),
  pubsub_server: WebRTCLive.PubSub,
  check_origin: ["//localhost:4000", "//127.0.0.1:4000"]

config :phoenix, :json_library, Jason
config :logger, level: :info
config :webrtc_live, ice_servers: []

if config_env() == :test do
  config :webrtc_live, WebRTCLive.Endpoint, server: false
  config :logger, level: :warning
end
