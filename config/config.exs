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
config :phoenix, :filter_parameters, ["token", "authorization"]
config :logger, level: :info
config :webrtc_live, ice_servers: []

config :webrtc_live,
  demo_tokens: config_env() == :dev,
  max_rooms: 100,
  max_sessions: 200,
  connect_timeout_ms: 30_000

if config_env() == :test do
  config :webrtc_live, WebRTCLive.Endpoint, server: false
  config :logger, level: :warning
end
