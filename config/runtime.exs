import Config

if config_env() == :prod do
  host = System.fetch_env!("HOST")

  config :webrtc_live, WebRTCLive.Endpoint,
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    url: [host: host, scheme: "https", port: 443],
    http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT", "4000"))],
    check_origin: ["https://#{host}"]

  {:ok, public_ip} =
    System.fetch_env!("PUBLIC_IP") |> String.to_charlist() |> :inet.parse_address()

  config :webrtc_live,
    public_ip: public_ip,
    ice_port_range: 50_000..50_100,
    max_rooms: String.to_integer(System.get_env("MAX_ROOMS", "5")),
    max_sessions: String.to_integer(System.get_env("MAX_SESSIONS", "20"))
end

if servers = System.get_env("ICE_SERVERS_JSON") do
  config :webrtc_live, :ice_servers, Jason.decode!(servers)
end

if secret = System.get_env("TURN_SECRET") do
  if byte_size(secret) < 32 or String.starts_with?(secret, "replace-") do
    raise "TURN_SECRET must be a randomly generated secret of at least 32 bytes"
  end

  turn_host = System.get_env("TURN_HOST") || System.fetch_env!("HOST")

  config :webrtc_live, :turn, %{
    secret: secret,
    ttl: 86_400,
    urls: ["turn:#{turn_host}:3478?transport=udp", "turn:#{turn_host}:3478?transport=tcp"]
  }
end
