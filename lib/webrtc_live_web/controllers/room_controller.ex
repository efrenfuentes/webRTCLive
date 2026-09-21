defmodule WebRTCLiveWeb.RoomController do
  use WebRTCLiveWeb, :controller
  alias WebRTCLive.{Calls, Accounts}

  def index(conn, _) do
    render(conn, :index, rooms: Calls.list(conn.assigns.current_scope.user))
  end

  def create(conn, %{"slug" => slug}) do
    case Calls.create(conn.assigns.current_scope.user, slug) do
      {:ok, room} ->
        redirect(conn, to: ~p"/rooms/#{room.slug}")

      {:error, _} ->
        conn
        |> put_flash(
          :error,
          "Choose an unused room name: letters, numbers, hyphens or underscores (1–64 characters)."
        )
        |> redirect(to: ~p"/")
    end
  end

  def show(conn, %{"slug" => slug}) do
    case Calls.access(conn.assigns.current_scope.user, slug) do
      {room, role} -> render(conn, :show, room: room, role: role)
      nil -> send_resp(conn, 404, "Room not found")
    end
  end

  def join(conn, %{"slug" => slug}) do
    case Calls.access(conn.assigns.current_scope.user, slug) do
      {room, role} ->
        {:ok, token} =
          WebRTCLive.Access.issue_for_session(room.slug, role, get_session(conn, :user_token))

        conn |> put_resp_header("cache-control", "no-store") |> json(%{token: token, role: role})

      nil ->
        conn |> put_status(403) |> json(%{error: "forbidden"})
    end
  end

  def invite(conn, %{"slug" => slug, "email" => email, "role" => role}) do
    result =
      with {:ok, user} <- Calls.invite(conn.assigns.current_scope.user, slug, email, role) do
        Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))
      end

    message =
      case result do
        {:ok, _} ->
          "Invitation sent."

        _ ->
          "Invitation could not be sent. Check the email, permissions and email delivery configuration."
      end

    conn |> put_flash(:info, message) |> redirect(to: ~p"/rooms/#{slug}")
  end
end
