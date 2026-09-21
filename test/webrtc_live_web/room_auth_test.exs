defmodule WebRTCLiveWeb.RoomAuthTest do
  use WebRTCLiveWeb.ConnCase, async: true
  import WebRTCLive.AccountsFixtures
  import Ecto.Query
  alias WebRTCLive.{Accounts, Calls, Access}

  test "anonymous users cannot issue room tokens and public registration is absent", %{conn: conn} do
    assert redirected_to(post(conn, "/rooms/demo/join")) == "/users/log-in"
    assert get(conn, "/users/register").status == 404
    assert post(conn, "/users/register", %{user: %{email: "stranger@example.com"}}).status == 404
    refute Accounts.get_user_by_email("stranger@example.com")
  end

  test "membership controls identity, room, and role; logout revokes grants", %{conn: conn} do
    owner = user_fixture()
    member = user_fixture()
    {:ok, room} = Calls.create(owner, "private-room")
    assert {:ok, _} = Calls.invite(owner, room.slug, member.email, "listener")
    conn = log_in_user(conn, member)
    response = post(conn, "/rooms/private-room/join", %{role: "participant", identity: "owner"})
    %{"token" => token, "role" => "listener"} = json_response(response, 200)
    assert {:ok, %{identity: identity, role: "listener"}} = Access.verify(token)
    assert identity == "u#{member.id}"
    assert {:error, :unauthorized} = Access.authorize(token, "other-room", "listener")
    assert {:error, :unauthorized} = Access.authorize(token, "private-room", "participant")
    response |> recycle() |> delete("/users/log-out")
    assert {:error, :unauthorized} = Access.verify(token)
  end

  test "unrelated user cannot read, join, or invite to a room", %{conn: conn} do
    owner = user_fixture()
    stranger = user_fixture()
    {:ok, room} = Calls.create(owner, "owners-room")
    conn = log_in_user(conn, stranger)
    assert get(conn, "/rooms/#{room.slug}").status == 404
    assert post(conn, "/rooms/#{room.slug}/join").status == 403

    assert {:error, :forbidden} =
             Calls.invite(stranger, room.slug, "target@example.com", "participant")

    refute Accounts.get_user_by_email("target@example.com")
  end

  test "magic-link preview does not consume token; login is single use", %{conn: conn} do
    user = unconfirmed_user_fixture()
    {token, _} = generate_user_magic_link_token(user)
    assert get(conn, "/users/log-in/#{token}").status == 200
    assert Accounts.get_user_by_magic_link_token(token)
    assert {:ok, _} = Accounts.login_user_by_magic_link(token)
    assert {:error, :not_found} = Accounts.login_user_by_magic_link(token)
    assert {:error, :not_found} = Accounts.login_user_by_magic_link("%%%")
  end

  test "permissions cannot be escalated through invitations" do
    user = user_fixture()
    {:ok, room} = Calls.create(user, "role-room")
    assert {:error, :invalid_role} = Calls.invite(user, room.slug, "target@example.com", "admin")
  end

  test "CSRF is required for a browser join request", %{conn: conn} do
    conn =
      conn
      |> log_in_user(user_fixture())
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      post(conn, "/rooms/demo/join")
    end
  end

  test "owner confirms deletion; memberships are removed but accounts remain", %{conn: conn} do
    owner = user_fixture()
    member = user_fixture()
    {:ok, room} = Calls.create(owner, "delete-owned-room")
    {:ok, _} = Calls.invite(owner, room.slug, member.email, "listener")
    session = Accounts.generate_user_session_token(member)
    {:ok, token} = Access.issue_for_session(room.slug, "listener", session)
    conn = log_in_user(conn, owner)
    assert html_response(get(conn, "/"), 200) =~ "Delete room"

    assert html_response(get(conn, "/rooms/#{room.slug}/delete"), 200) =~
             "Permanently delete room"

    assert Calls.access(owner, room.slug)
    response = delete(conn, "/rooms/#{room.slug}", %{room_id: to_string(room.id)})
    assert redirected_to(response) == "/"
    refute Calls.access(owner, room.slug)
    refute Calls.access(member, room.slug)
    assert Accounts.get_user!(member.id)

    refute WebRTCLive.Repo.exists?(
             from(m in WebRTCLive.Calls.Membership, where: m.room_id == ^room.id)
           )

    assert {:error, :unauthorized} = Access.verify(token)
    {:ok, replacement} = Calls.create(owner, room.slug)
    {:ok, _} = Calls.invite(owner, room.slug, member.email, "listener")
    assert {:error, :unauthorized} = Access.verify(token)
    assert {:error, :stale_room} = Calls.delete(owner, replacement.slug, room.id)
    assert Calls.access(owner, replacement.slug)
  end

  test "members and outsiders cannot delete or see deletion controls", %{conn: conn} do
    owner = user_fixture()
    member = user_fixture()
    {:ok, room} = Calls.create(owner, "delete-permissions")
    {:ok, _} = Calls.invite(owner, room.slug, member.email, "participant")
    conn = log_in_user(conn, member)
    refute html_response(get(conn, "/rooms/#{room.slug}"), 200) =~ "Delete room"
    assert get(conn, "/rooms/#{room.slug}/delete").status == 404
    assert delete(conn, "/rooms/#{room.slug}", %{room_id: to_string(room.id)}).status == 404
    assert {:error, :forbidden} = Calls.delete(user_fixture(), room.slug, room.id)
    assert Calls.access(owner, room.slug)
  end

  test "active rooms cannot be deleted", %{conn: conn} do
    owner = user_fixture()
    {:ok, room} = Calls.create(owner, "delete-active-room")
    {:ok, live_room} = WebRTCLive.Room.get_or_start(room.slug)

    on_exit(fn ->
      if Process.alive?(live_room),
        do: DynamicSupervisor.terminate_child(WebRTCLive.RoomSupervisor, live_room)
    end)

    conn = log_in_user(conn, owner)
    response = delete(conn, "/rooms/#{room.slug}", %{room_id: to_string(room.id)})
    assert redirected_to(response) == "/rooms/#{room.slug}"
    assert Phoenix.Flash.get(response.assigns.flash, :error) =~ "active"
    assert Calls.access(owner, room.slug)
    assert Process.alive?(live_room)
  end

  test "deletion requires login and CSRF protection", %{conn: conn} do
    assert redirected_to(delete(conn, "/rooms/test", %{room_id: "1"})) == "/users/log-in"
    conn = conn |> log_in_user(user_fixture()) |> put_private(:plug_skip_csrf_protection, false)

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      delete(conn, "/rooms/test", %{room_id: "1"})
    end
  end
end
