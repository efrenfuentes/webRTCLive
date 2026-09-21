defmodule WebRTCLiveWeb.RoomAuthTest do
  use WebRTCLiveWeb.ConnCase, async: true
  import WebRTCLive.AccountsFixtures
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
end
