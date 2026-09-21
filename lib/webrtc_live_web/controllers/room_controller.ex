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
        case WebRTCLive.Access.issue_for_session(room.slug, role, get_session(conn, :user_token)) do
          {:ok, token} ->
            conn
            |> put_resp_header("cache-control", "no-store")
            |> json(%{token: token, role: role})

          {:error, _} ->
            conn |> put_status(403) |> json(%{error: "forbidden"})
        end

      nil ->
        conn |> put_status(403) |> json(%{error: "forbidden"})
    end
  end

  def confirm_delete(conn, %{"slug" => slug}) do
    user = conn.assigns.current_scope.user

    case Calls.access(user, slug) do
      {%{owner_id: owner_id} = room, _} when owner_id == user.id ->
        render(conn, :delete, room: room)

      _ ->
        send_resp(conn, 404, "Room not found")
    end
  end

  def delete(conn, %{"slug" => slug, "room_id" => room_id}) when is_binary(room_id) do
    case Calls.delete(conn.assigns.current_scope.user, slug, room_id) do
      {:ok, _} ->
        conn |> put_flash(:info, "Room deleted.") |> redirect(to: ~p"/")

      {:error, :room_active} ->
        conn
        |> put_flash(:error, "This room is active. Ask everyone to leave, then try again.")
        |> redirect(to: ~p"/rooms/#{slug}")

      {:error, :stale_room} ->
        conn
        |> put_flash(:error, "This room has changed. Review it before deleting.")
        |> redirect(to: ~p"/")

      {:error, _} ->
        send_resp(conn, 404, "Room not found")
    end
  end

  def delete(conn, _), do: send_resp(conn, 400, "Room confirmation is required")

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
