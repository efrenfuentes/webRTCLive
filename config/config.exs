import Config

config :webrtc_live, :scopes,
  user: [
    default: true,
    module: WebRTCLive.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: WebRTCLive.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :webrtc_live, namespace: WebRTCLive, ecto_repos: [WebRTCLive.Repo]

config :webrtc_live, WebRTCLive.Repo,
  url:
    System.get_env(
      "DATABASE_URL",
      "postgres://postgres:postgres@localhost:5433/webrtc_live_#{config_env()}"
    ),
  pool_size: 5,
  template: "template0"

config :webrtc_live, WebRTCLive.Mailer, adapter: Swoosh.Adapters.Local
config :swoosh, :api_client, Swoosh.ApiClient.Req

if config_env() == :prod do
  config :webrtc_live, WebRTCLive.Endpoint, force_ssl: [rewrite_on: [:x_forwarded_proto]]
end

if config_env() == :test do
  config :webrtc_live, WebRTCLive.Repo, pool: Ecto.Adapters.SQL.Sandbox
  config :webrtc_live, WebRTCLive.Mailer, adapter: Swoosh.Adapters.Test
end

config :webrtc_live, WebRTCLive.Endpoint,
  render_errors: [
    formats: [html: WebRTCLiveWeb.ErrorHTML, json: WebRTCLiveWeb.ErrorJSON],
    layout: false
  ],
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: 4000],
  server: true,
  secret_key_base: String.duplicate("local-development-only-", 4),
  pubsub_server: WebRTCLive.PubSub,
  check_origin: ["//localhost:4000", "//127.0.0.1:4000"]

config :phoenix, :json_library, Jason

config :phoenix, :filter_parameters, [
  "token",
  "authorization",
  "password",
  "password_confirmation"
]

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
  import_config "test.exs"
end
