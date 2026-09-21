defmodule WebRTCLive.Calls.Room do
  use Ecto.Schema

  schema "call_rooms" do
    field(:slug, :string)
    belongs_to(:owner, WebRTCLive.Accounts.User)
    timestamps()
  end
end

defmodule WebRTCLive.Calls.Membership do
  use Ecto.Schema

  schema "room_memberships" do
    belongs_to(:room, WebRTCLive.Calls.Room)
    belongs_to(:user, WebRTCLive.Accounts.User)
    field(:role, :string)
    timestamps()
  end
end

defmodule WebRTCLive.Calls do
  import Ecto.Query
  import Ecto.Changeset
  alias WebRTCLive.{Repo, Accounts}
  alias WebRTCLive.Calls.{Room, Membership}

  def list(user) do
    Repo.all(
      from(r in Room,
        join: m in Membership,
        on: m.room_id == r.id,
        where: m.user_id == ^user.id,
        order_by: r.slug,
        select: {r, m.role}
      )
    )
  end

  def access(user, slug) do
    Repo.one(
      from(r in Room,
        join: m in Membership,
        on: m.room_id == r.id,
        where: r.slug == ^slug and m.user_id == ^user.id,
        select: {r, m.role}
      )
    )
  end

  def create(user, slug) when is_binary(slug) do
    Repo.transaction(fn ->
      changeset =
        %Room{}
        |> cast(%{slug: slug}, [:slug])
        |> validate_required([:slug])
        |> validate_format(:slug, ~r/^[a-zA-Z0-9_-]{1,64}$/)
        |> put_change(:owner_id, user.id)
        |> unique_constraint(:slug)

      case Repo.insert(changeset) do
        {:ok, room} ->
          Repo.insert!(%Membership{room_id: room.id, user_id: user.id, role: "participant"})
          room

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def delete(owner, slug, room_id) do
    Repo.transaction(fn ->
      room =
        Repo.one(
          from(r in Room, where: r.slug == ^slug and r.owner_id == ^owner.id, lock: "FOR UPDATE")
        )

      cond do
        is_nil(room) -> Repo.rollback(:forbidden)
        to_string(room.id) != to_string(room_id) -> Repo.rollback(:stale_room)
        Registry.lookup(WebRTCLive.Registry, slug) != [] -> Repo.rollback(:room_active)
        true -> Repo.delete!(room)
      end
    end)
  end

  # Serialize authenticated joins with deletion: after this lock is released,
  # an admitted room is registered and deletion will reject it as active.
  def with_join_lock(%{session_id: _, room_id: room_id}, fun) do
    case Repo.transaction(fn ->
           if Repo.one(from(r in Room, where: r.id == ^room_id, lock: "FOR SHARE")) do
             fun.()
           else
             {:error, %{reason: :unauthorized}}
           end
         end) do
      {:ok, result} -> result
      {:error, _} -> {:error, %{reason: :unauthorized}}
    end
  end

  def with_join_lock(_service_claims, fun), do: fun.()

  def invite(owner, slug, email, role) when role in ~w(participant publisher listener) do
    case access(owner, slug) do
      {%Room{owner_id: owner_id} = room, _} when owner_id == owner.id ->
        Repo.transaction(fn ->
          user =
            case Accounts.get_user_by_email(email) do
              nil ->
                case Accounts.register_user(%{email: email}) do
                  {:ok, user} -> user
                  {:error, reason} -> Repo.rollback(reason)
                end

              user ->
                user
            end

          %Membership{}
          |> change(room_id: room.id, user_id: user.id, role: role)
          |> Repo.insert!(on_conflict: [set: [role: role]], conflict_target: [:room_id, :user_id])

          user
        end)

      _ ->
        {:error, :forbidden}
    end
  end

  def invite(_, _, _, _), do: {:error, :invalid_role}
end
