defmodule WebRTCLive.Repo.Migrations.CreateCallRooms do
  use Ecto.Migration
  def change do
    alter table(:users) do
      add :admin, :boolean, default: false, null: false
    end
    create table(:call_rooms) do
      add :slug, :string, null: false
      add :owner_id, references(:users), null: false
      timestamps()
    end
    create unique_index(:call_rooms, [:slug])
    create table(:room_memberships) do
      add :room_id, references(:call_rooms, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role, :string, null: false
      timestamps()
    end
    create unique_index(:room_memberships, [:room_id, :user_id])
    create constraint(:room_memberships, :valid_role, check: "role IN ('participant', 'publisher', 'listener')")
  end
end
