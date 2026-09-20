import Config

if config_env() == :prod do
  host = System.fetch_env!("HOST")

  config :webrtc_live, WebRTCLive.Endpoint,
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    url: [host: host, scheme: "https", port: 443],
    http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4000"))],
    check_origin: ["https://#{host}"]
end

if servers = System.get_env("ICE_SERVERS_JSON") do
  config :webrtc_live, :ice_servers, Jason.decode!(servers)
end
