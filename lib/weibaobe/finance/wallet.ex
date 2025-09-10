defmodule Weibaobe.Finance.Wallet do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:wallet_id, :string, []}

  schema "wallets" do
    field :user_id, :string
    field :user_phone_number, :string
    field :user_name, :string
    field :coins_balance, :integer, default: 0

    timestamps(type: :utc_datetime)

    # Associations
    belongs_to :user, Weibaobe.Accounts.User, foreign_key: :user_id, references: :uid, type: :string, define_field: false
    has_many :transactions, Weibaobe.Finance.WalletTransaction, foreign_key: :wallet_id, references: :wallet_id
  end

  def changeset(wallet, attrs) do
    wallet
    |> cast(attrs, [:wallet_id, :user_id, :user_phone_number, :user_name, :coins_balance])
    |> validate_required([:wallet_id, :user_id, :user_phone_number, :user_name])
    |> validate_number(:coins_balance, greater_than_or_equal_to: 0)
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end

  def create_changeset(wallet, attrs) do
    wallet
    |> cast(attrs, [:wallet_id, :user_id, :user_phone_number, :user_name])
    |> validate_required([:wallet_id, :user_id, :user_phone_number, :user_name])
    |> put_change(:coins_balance, 0)
    |> unique_constraint(:user_id)
  end
end

defmodule Weibaobe.Finance.WalletTransaction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:transaction_id, Ecto.UUID, autogenerate: true}

  schema "wallet_transactions" do
    field :wallet_id, :string
    field :user_id, :string
    field :user_phone_number, :string
    field :user_name, :string
    field :type, :string
    field :coin_amount, :integer
    field :balance_before, :integer
    field :balance_after, :integer
    field :description, :string, default: ""
    field :reference_id, :string
    field :admin_note, :string
    field :payment_method, :string
    field :payment_reference, :string
    field :package_id, :string
    field :paid_amount, :decimal
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime, updated_at: false)

    # Associations
    belongs_to :wallet, Weibaobe.Finance.Wallet, foreign_key: :wallet_id, references: :wallet_id, type: :string, define_field: false
    belongs_to :user, Weibaobe.Accounts.User, foreign_key: :user_id, references: :uid, type: :string, define_field: false
  end

  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :wallet_id, :user_id, :user_phone_number, :user_name, :type,
      :coin_amount, :balance_before, :balance_after, :description,
      :reference_id, :admin_note, :payment_method, :payment_reference,
      :package_id, :paid_amount, :metadata
    ])
    |> validate_required([
      :wallet_id, :user_id, :user_phone_number, :user_name, :type,
      :coin_amount, :balance_before, :balance_after
    ])
    |> validate_inclusion(:type, [
      "admin_credit", "admin_debit", "coin_purchase", "coin_usage",
      "reward", "refund", "transfer"
    ])
    |> validate_number(:balance_before, greater_than_or_equal_to: 0)
    |> validate_number(:balance_after, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:wallet_id)
    |> foreign_key_constraint(:user_id)
  end
end

defmodule Weibaobe.Finance.CoinPurchaseRequest do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "coin_purchase_requests" do
    field :user_id, :string
    field :package_id, :string
    field :coin_amount, :integer
    field :paid_amount, :decimal
    field :payment_reference, :string
    field :payment_method, :string
    field :status, :string, default: "pending_admin_verification"
    field :requested_at, :utc_datetime
    field :processed_at, :utc_datetime
    field :admin_note, :string

    # Associations
    belongs_to :user, Weibaobe.Accounts.User, foreign_key: :user_id, references: :uid, type: :string, define_field: false
  end

  def changeset(request, attrs) do
    request
    |> cast(attrs, [
      :user_id, :package_id, :coin_amount, :paid_amount, :payment_reference,
      :payment_method, :status, :requested_at, :processed_at, :admin_note
    ])
    |> validate_required([
      :user_id, :package_id, :coin_amount, :paid_amount,
      :payment_reference, :payment_method
    ])
    |> validate_inclusion(:status, [
      "pending_admin_verification", "approved", "rejected", "cancelled"
    ])
    |> validate_inclusion(:package_id, ["coins_99", "coins_495", "coins_990"])
    |> validate_number(:coin_amount, greater_than: 0)
    |> validate_number(:paid_amount, greater_than: 0)
    |> put_change(:requested_at, DateTime.utc_now())
    |> foreign_key_constraint(:user_id)
  end

  def approve_changeset(request, admin_note \\ nil) do
    request
    |> change(
      status: "approved",
      processed_at: DateTime.utc_now(),
      admin_note: admin_note
    )
  end

  def reject_changeset(request, admin_note) do
    request
    |> change(
      status: "rejected",
      processed_at: DateTime.utc_now(),
      admin_note: admin_note
    )
  end
end

defmodule Weibaobe.Finance.CoinPackages do
  @moduledoc """
  Coin package definitions and pricing
  """

  @packages %{
    "coins_99" => %{coins: 99, price: Decimal.new("100.0"), name: "Starter Pack"},
    "coins_495" => %{coins: 495, price: Decimal.new("500.0"), name: "Popular Pack"},
    "coins_990" => %{coins: 990, price: Decimal.new("1000.0"), name: "Value Pack"}
  }

  @drama_unlock_cost 99

  def all_packages, do: @packages

  def get_package(package_id), do: Map.get(@packages, package_id)

  def valid_package?(package_id), do: Map.has_key?(@packages, package_id)

  def drama_unlock_cost, do: @drama_unlock_cost

  def package_ids, do: Map.keys(@packages)
end
