defmodule WebRTCLiveWeb.UserSessionHTML do
  use WebRTCLiveWeb, :html

  embed_templates("user_session_html/*")

  defp local_mail_adapter? do
    Application.get_env(:webrtc_live, WebRTCLive.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
