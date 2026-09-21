defmodule WebRTCLive.Release do
  @moduledoc "Release database maintenance and first-administrator invitation."
  def migrate do
    Application.load(:webrtc_live)
    {:ok, _, _} = Ecto.Migrator.with_repo(WebRTCLive.Repo, &Ecto.Migrator.run(&1, :up, all: true))
    :ok
  end

  def invite_admin(email) do
    alias WebRTCLive.{Accounts, Repo}
    import Ecto.Query

    user =
      Repo.transaction(fn ->
        # Serialize bootstrap attempts; never promote an existing ordinary account.
        Repo.query!("SELECT pg_advisory_xact_lock(9274021)")

        case Accounts.get_user_by_email(email) do
          %{admin: true} = user ->
            user

          nil ->
            if Repo.exists?(from(u in Accounts.User, where: u.admin)),
              do: Repo.rollback(:admin_exists)

            {:ok, user} = Accounts.register_user(%{email: email})
            user |> Ecto.Changeset.change(admin: true) |> Repo.update!()

          _ ->
            Repo.rollback(:existing_non_admin)
        end
      end)

    with {:ok, user} <- user do
      Accounts.deliver_login_instructions(
        user,
        &(WebRTCLive.Endpoint.url() <> "/users/log-in/" <> &1)
      )
      |> case do
        {:ok, _} -> :ok
        {:error, _} -> {:error, :email_delivery_failed}
      end
    end
  end
end
