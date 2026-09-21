defmodule WebRTCLiveWeb.ErrorHTML do
  def render(template, _), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule WebRTCLiveWeb.ErrorJSON do
  def render(template, _), do: %{error: Phoenix.Controller.status_message_from_template(template)}
end
