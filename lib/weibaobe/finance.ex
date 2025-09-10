defmodule Weibaobe.Finance do
  @moduledoc """
  The Finance context for managing wallets, coins, and transactions.
  """

  import Ecto.Query, warn: false
  alias Weibaobe.Repo
  alias Weibaobe.Finance.{Wallet, WalletTransaction, CoinPurchaseRequest, CoinPackages}
  alias Weibaobe.Accounts.User

  # ===============================
  # WALLET OPERATIONS
  # ===============================

  @doc """
  Gets or creates a wallet for a user.
  """
  def get_or_create_wallet(user_id) do
    case Repo.get(Wallet, user_id) do
      nil ->
        create_wallet_for_user(user_id)

      wallet ->
        {:ok, wallet}
    end
  end

  @doc """
  Gets a wallet by user ID.
  """
  def get_wallet(user_id) do
    case Repo.get(Wallet, user_id) do
      nil -> {:error, :not_found}
      wallet -> {:ok, wallet}
    end
  end

  @doc """
  Creates a wallet for a user.
  """
  def create_wallet_for_user(user_id) do
    case Weibaobe.Accounts.get_user(user_id) do
      {:ok, user} ->
        %Wallet{}
        |> Wallet.create_changeset(%{
          wallet_id: user_id,
          user_id: user_id,
          user_phone_number: user.phone_number,
          user_name: user.name
        })
        |> Repo.insert()

      error -> error
    end
  end

  # ===============================
  # COIN OPERATIONS
  # ===============================

  @doc """
  Adds coins to a user's wallet (admin operation).
  """
  def add_coins(user_id, coin_amount, description \\ "Admin added coins", admin_note \\ nil) do
    Repo.transaction(fn ->
      # Get or create wallet
      {:ok, wallet} = get_or_create_wallet(user_id)

      # Calculate new balance
      new_balance = wallet.coins_balance + coin_amount

      # Update wallet
      wallet_changeset = wallet
                        |> Ecto.Changeset.change(coins_balance: new_balance, updated_at: DateTime.utc_now())

      {:ok, updated_wallet} = Repo.update(wallet_changeset)

      # Create transaction record
      transaction_attrs = %{
        wallet_id: wallet.wallet_id,
        user_id: user_id,
        user_phone_number: wallet.user_phone_number,
        user_name: wallet.user_name,
        type: "admin_credit",
        coin_amount: coin_amount,
        balance_before: wallet.coins_balance,
        balance_after: new_balance,
        description: description,
        admin_note: admin_note
      }

      {:ok, _transaction} = create_transaction(transaction_attrs)

      new_balance
    end)
    |> case do
      {:ok, new_balance} -> {:ok, new_balance}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deducts coins from a user's wallet.
  """
  def deduct_coins(user_id, coin_amount, description \\ "Coins used", reference_id \\ nil) do
    Repo.transaction(fn ->
      # Get wallet
      case get_wallet(user_id) do
        {:ok, wallet} ->
          if wallet.coins_balance >= coin_amount do
            # Calculate new balance
            new_balance = wallet.coins_balance - coin_amount

            # Update wallet
            wallet_changeset = wallet
                              |> Ecto.Changeset.change(coins_balance: new_balance, updated_at: DateTime.utc_now())

            {:ok, updated_wallet} = Repo.update(wallet_changeset)

            # Create transaction record
            transaction_attrs = %{
              wallet_id: wallet.wallet_id,
              user_id: user_id,
              user_phone_number: wallet.user_phone_number,
              user_name: wallet.user_name,
              type: "coin_usage",
              coin_amount: -coin_amount,
              balance_before: wallet.coins_balance,
              balance_after: new_balance,
              description: description,
              reference_id: reference_id
            }

            {:ok, _transaction} = create_transaction(transaction_attrs)

            new_balance
          else
            Repo.rollback(:insufficient_balance)
          end

        {:error, :not_found} ->
          Repo.rollback(:wallet_not_found)
      end
    end)
    |> case do
      {:ok, new_balance} -> {:ok, new_balance}
      {:error, reason} -> {:error, reason}
    end
  end

  # ===============================
  # TRANSACTION OPERATIONS
  # ===============================

  @doc """
  Creates a wallet transaction record.
  """
  def create_transaction(attrs) do
    %WalletTransaction{}
    |> WalletTransaction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets transaction history for a user's wallet.
  """
  def get_user_transactions(user_id, limit \\ 50) do
    WalletTransaction
    |> where([wt], wt.user_id == ^user_id)
    |> order_by([wt], desc: wt.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets all transactions (admin only).
  """
  def get_all_transactions(user_id, limit \\ 100, offset \\ 0) do
    if is_admin?(user_id) do
      WalletTransaction
      |> order_by([wt], desc: wt.inserted_at)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()
    else
      {:error, :access_denied}
    end
  end

  # ===============================
  # COIN PURCHASE OPERATIONS
  # ===============================

  @doc """
  Creates a coin purchase request.
  """
  def create_purchase_request(attrs) do
    # Validate package exists
    package_id = attrs["package_id"] || attrs[:package_id]

    case CoinPackages.get_package(package_id) do
      nil ->
        {:error, :invalid_package}

      package ->
        # Ensure correct amounts
        purchase_attrs = Map.merge(attrs, %{
          "coin_amount" => package.coins,
          "paid_amount" => package.price
        })

        %CoinPurchaseRequest{}
        |> CoinPurchaseRequest.changeset(purchase_attrs)
        |> Repo.insert()
    end
  end

  @doc """
  Gets pending purchase requests (admin only).
  """
  def get_pending_purchases(user_id, limit \\ 50) do
    if is_admin?(user_id) do
      CoinPurchaseRequest
      |> where([cpr], cpr.status == "pending_admin_verification")
      |> order_by([cpr], desc: cpr.requested_at)
      |> limit(^limit)
      |> Repo.all()
    else
      {:error, :access_denied}
    end
  end

  @doc """
  Gets purchase requests for a user.
  """
  def get_user_purchase_requests(user_id, limit \\ 20) do
    CoinPurchaseRequest
    |> where([cpr], cpr.user_id == ^user_id)
    |> order_by([cpr], desc: cpr.requested_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Approves a coin purchase request (admin only).
  """
  def approve_purchase_request(request_id, admin_note \\ nil, admin_user_id) do
    if is_admin?(admin_user_id) do
      Repo.transaction(fn ->
        # Get the purchase request
        case Repo.get(CoinPurchaseRequest, request_id) do
          nil ->
            Repo.rollback(:request_not_found)

          %CoinPurchaseRequest{status: "pending_admin_verification"} = request ->
            # Add coins to user's wallet
            case add_coins(request.user_id, request.coin_amount, "Coin purchase approved", admin_note) do
              {:ok, _new_balance} ->
                # Update request status
                request
                |> CoinPurchaseRequest.approve_changeset(admin_note)
                |> Repo.update!()

              {:error, reason} ->
                Repo.rollback(reason)
            end

          request ->
            Repo.rollback({:invalid_status, request.status})
        end
      end)
      |> case do
        {:ok, request} -> {:ok, request}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :access_denied}
    end
  end

  @doc """
  Rejects a coin purchase request (admin only).
  """
  def reject_purchase_request(request_id, admin_note, admin_user_id) do
    if is_admin?(admin_user_id) do
      case Repo.get(CoinPurchaseRequest, request_id) do
        nil ->
          {:error, :not_found}

        %CoinPurchaseRequest{status: "pending_admin_verification"} = request ->
          request
          |> CoinPurchaseRequest.reject_changeset(admin_note)
          |> Repo.update()

        request ->
          {:error, {:invalid_status, request.status}}
      end
    else
      {:error, :access_denied}
    end
  end

  # ===============================
  # ANALYTICS AND STATISTICS
  # ===============================

  @doc """
  Gets wallet statistics for a user.
  """
  def get_user_wallet_stats(user_id) do
    case get_wallet(user_id) do
      {:ok, wallet} ->
        # Get transaction counts by type
        transaction_stats = from(wt in WalletTransaction,
                               where: wt.user_id == ^user_id,
                               group_by: wt.type,
                               select: {wt.type, count(wt.id)})
                          |> Repo.all()
                          |> Map.new()

        # Get total spent and earned
        spending_stats = from(wt in WalletTransaction,
                            where: wt.user_id == ^user_id,
                            select: %{
                              total_earned: sum(fragment("CASE WHEN coin_amount > 0 THEN coin_amount ELSE 0 END")),
                              total_spent: sum(fragment("CASE WHEN coin_amount < 0 THEN ABS(coin_amount) ELSE 0 END"))
                            })
                       |> Repo.one()

        stats = %{
          wallet: wallet,
          transaction_counts: transaction_stats,
          total_earned: spending_stats.total_earned || 0,
          total_spent: spending_stats.total_spent || 0
        }

        {:ok, stats}

      error -> error
    end
  end

  @doc """
  Gets platform financial statistics (admin only).
  """
  def get_platform_financial_stats(user_id) do
    if is_admin?(user_id) do
      # Total coins in circulation
      total_coins = from(w in Wallet, select: sum(w.coins_balance))
                   |> Repo.one() || 0

      # Purchase request statistics
      purchase_stats = from(cpr in CoinPurchaseRequest,
                          group_by: cpr.status,
                          select: {cpr.status, count(cpr.id)})
                     |> Repo.all()
                     |> Map.new()

      # Revenue from approved purchases
      total_revenue = from(cpr in CoinPurchaseRequest,
                         where: cpr.status == "approved",
                         select: sum(cpr.paid_amount))
                    |> Repo.one() || Decimal.new(0)

      # Recent financial activity
      recent_transactions = from(wt in WalletTransaction,
                               where: wt.inserted_at > ago(7, "day"),
                               group_by: fragment("DATE(?)", wt.inserted_at),
                               order_by: [desc: fragment("DATE(?)", wt.inserted_at)],
                               select: %{
                                 date: fragment("DATE(?)", wt.inserted_at),
                                 transaction_count: count(wt.id),
                                 coins_transacted: sum(fragment("ABS(?)", wt.coin_amount))
                               })
                          |> Repo.all()

      stats = %{
        total_coins_in_circulation: total_coins,
        purchase_request_stats: purchase_stats,
        total_revenue: total_revenue,
        recent_activity: recent_transactions
      }

      {:ok, stats}
    else
      {:error, :access_denied}
    end
  end

  @doc """
  Gets top spenders (admin only).
  """
  def get_top_spenders(user_id, limit \\ 10) do
    if is_admin?(user_id) do
      from(wt in WalletTransaction,
           join: u in User, on: wt.user_id == u.uid,
           where: wt.coin_amount < 0,
           group_by: [wt.user_id, u.name, u.phone_number],
           order_by: [desc: sum(fragment("ABS(?)", wt.coin_amount))],
           limit: ^limit,
           select: %{
             user_id: wt.user_id,
             user_name: u.name,
             phone_number: u.phone_number,
             total_spent: sum(fragment("ABS(?)", wt.coin_amount))
           })
      |> Repo.all()
    else
      {:error, :access_denied}
    end
  end

  # ===============================
  # COIN PACKAGE UTILITIES
  # ===============================

  @doc """
  Gets all available coin packages.
  """
  def get_coin_packages do
    CoinPackages.all_packages()
  end

  @doc """
  Gets a specific coin package.
  """
  def get_coin_package(package_id) do
    case CoinPackages.get_package(package_id) do
      nil -> {:error, :not_found}
      package -> {:ok, package}
    end
  end

  @doc """
  Validates a coin package ID.
  """
  def valid_package?(package_id) do
    CoinPackages.valid_package?(package_id)
  end

  @doc """
  Gets the drama unlock cost.
  """
  def drama_unlock_cost do
    CoinPackages.drama_unlock_cost()
  end

  # ===============================
  # HELPER FUNCTIONS
  # ===============================

  defp is_admin?(user_id) do
    case Weibaobe.Accounts.get_user(user_id) do
      {:ok, %{user_type: "admin"}} -> true
      _ -> false
    end
  end

  @doc """
  Formats currency amounts for display.
  """
  def format_currency(amount) when is_number(amount) do
    amount
    |> Decimal.from_float()
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  def format_currency(%Decimal{} = amount) do
    amount
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  def format_currency(_), do: "0.00"

  @doc """
  Checks if user has sufficient balance for a purchase.
  """
  def sufficient_balance?(user_id, required_coins) do
    case get_wallet(user_id) do
      {:ok, wallet} -> wallet.coins_balance >= required_coins
      {:error, _} -> false
    end
  end

  @doc """
  Gets wallet balance for a user.
  """
  def get_balance(user_id) do
    case get_wallet(user_id) do
      {:ok, wallet} -> {:ok, wallet.coins_balance}
      error -> error
    end
  end

  @doc """
  Transfers coins between users (admin operation).
  """
  def transfer_coins(from_user_id, to_user_id, coin_amount, description \\ "Coin transfer", admin_user_id) do
    if is_admin?(admin_user_id) do
      Repo.transaction(fn ->
        # Deduct from sender
        case deduct_coins(from_user_id, coin_amount, description, "transfer_out") do
          {:ok, _} ->
            # Add to receiver
            case add_coins(to_user_id, coin_amount, description, "Admin transfer") do
              {:ok, new_balance} -> new_balance
              {:error, reason} -> Repo.rollback(reason)
            end

          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :access_denied}
    end
  end
end
