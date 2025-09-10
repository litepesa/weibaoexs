defmodule Weibaobe.Repo do
  use Ecto.Repo,
    otp_app: :weibaobe,
    adapter: Ecto.Adapters.Postgres
end
