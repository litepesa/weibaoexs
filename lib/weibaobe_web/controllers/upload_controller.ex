defmodule WeibaobeWeb.UploadController do
  use WeibaobeWeb, :controller

  alias Weibaobe.Services.R2Storage

  action_fallback WeibaobeWeb.FallbackController

  @doc """
  Upload a single file (REQUIRES AUTH)
  """
  def upload_file(conn, %{"file" => file_upload, "type" => file_type}) do
    # Validate file type and size
    case R2Storage.validate_upload(file_upload.filename, file_upload.path |> File.stat!() |> Map.get(:size), file_type) do
      {:ok, :valid} ->
        case R2Storage.upload_plug_file(file_upload, file_type) do
          {:ok, url} ->
            conn
            |> json(%{
              url: url,
              message: "File uploaded successfully",
              fileName: file_upload.filename,
              fileSize: File.stat!(file_upload.path).size,
              fileType: file_type,
              extension: Path.extname(file_upload.filename),
              timestamp: System.system_time(:second)
            })

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{
              error: "Failed to upload file",
              details: inspect(reason),
              fileName: file_upload.filename,
              timestamp: System.system_time(:second)
            })
        end

      {:error, {:invalid_extension, ext, allowed}} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "Invalid file type for #{file_type}",
          allowed: allowed,
          received: ext
        })

      {:error, {:file_too_large, size, max_size}} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "File too large",
          fileSizeMB: Float.round(size / (1024 * 1024), 2),
          maxSizeMB: Float.round(max_size / (1024 * 1024), 2)
        })
    end
  end

  def upload_file(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "File and type parameters are required"})
  end

  @doc """
  Upload multiple files (REQUIRES AUTH)
  """
  def batch_upload(conn, %{"files" => files, "type" => file_type}) when is_list(files) do
    case R2Storage.batch_upload(files, file_type) do
      {:ok, results} ->
        conn
        |> json(Map.merge(results, %{
          message: "Batch upload completed. #{results.successful} of #{results.total} files uploaded successfully",
          timestamp: System.system_time(:second)
        }))

      {:error, :too_many_files} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Too many files. Maximum 20 files allowed per batch"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Batch upload failed", details: inspect(reason)})
    end
  end

  def batch_upload(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "files array and type are required"})
  end

  @doc """
  Health check for upload service (REQUIRES AUTH)
  """
  def health_check(conn, _params) do
    case R2Storage.health_check() do
      {:ok, :healthy} ->
        conn
        |> json(%{
          status: "healthy",
          service: "upload",
          timestamp: System.system_time(:second),
          supportedFormats: %{
            images: [".jpg", ".jpeg", ".png", ".webp", ".gif"],
            videos: [".mp4", ".mov", ".avi", ".webm", ".ts", ".m3u8", ".mkv"]
          },
          maxSizesMB: %{
            banner: 10,
            thumbnail: 5,
            profile: 5,
            video: 1024
          }
        })

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "unhealthy",
          service: "upload",
          error: inspect(reason),
          timestamp: System.system_time(:second)
        })
    end
  end
end

defmodule WeibaobeWeb.WalletController do
  use WeibaobeWeb, :controller

  alias Weibaobe.Finance

  action_fallback WeibaobeWeb.FallbackController

  @doc """
  Get user's wallet (REQUIRES AUTH)
  """
  def show(conn, %{"userId" => user_id}) do
    requesting_user_id = conn.assigns.current_user_id

    # Users can only access their own wallet unless admin
    if requesting_user_id == user_id or is_admin?(conn.assigns.current_user) do
      case Finance.get_or_create_wallet(user_id) do
        {:ok, wallet} ->
          conn |> json(format_wallet_response(wallet))

        {:error, reason} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to fetch wallet", details: inspect(reason)})
      end
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Access denied"})
    end
  end

  @doc """
  Get user's transaction history (REQUIRES AUTH)
  """
  def transactions(conn, %{"userId" => user_id} = params) do
    requesting_user_id = conn.assigns.current_user_id

    if requesting_user_id == user_id or is_admin?(conn.assigns.current_user) do
      limit = parse_int(params["limit"], 50, 200)

      transactions = Finance.get_user_transactions(user_id, limit)
      formatted_transactions = Enum.map(transactions, &format_transaction_response/1)

      conn
      |> json(%{
        transactions: formatted_transactions,
        total: length(formatted_transactions)
      })
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Access denied"})
    end
  end

  @doc """
  Create coin purchase request (REQUIRES AUTH)
  """
  def create_purchase_request(conn, %{"userId" => user_id} = params) do
    requesting_user_id = conn.assigns.current_user_id

    if requesting_user_id == user_id do
      purchase_attrs = %{
        "user_id" => user_id,
        "package_id" => params["packageId"],
        "payment_reference" => params["paymentReference"],
        "payment_method" => params["paymentMethod"]
      }

      case Finance.create_purchase_request(purchase_attrs) do
        {:ok, request} ->
          conn
          |> put_status(:created)
          |> json(%{
            requestId: request.id,
            message: "Purchase request submitted for admin verification",
            status: "pending"
          })

        {:error, :invalid_package} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Invalid package ID"})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            error: "Failed to create purchase request",
            details: format_changeset_errors(changeset)
          })
      end
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Access denied"})
    end
  end

  @doc """
  Add coins to user wallet (ADMIN ONLY)
  """
  def add_coins(conn, %{"userId" => user_id} = params) do
    admin_user_id = conn.assigns.current_user_id
    coin_amount = params["coinAmount"]
    description = params["description"] || "Admin added coins"
    admin_note = params["adminNote"]

    cond do
      not is_integer(coin_amount) or coin_amount <= 0 or coin_amount > 10000 ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid coin amount"})

      true ->
        case Finance.add_coins(user_id, coin_amount, description, admin_note) do
          {:ok, new_balance} ->
            conn
            |> json(%{
              message: "Coins added successfully",
              newBalance: new_balance
            })

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to add coins", details: inspect(reason)})
        end
    end
  end

  @doc """
  Get pending purchase requests (ADMIN ONLY)
  """
  def pending_purchases(conn, params) do
    admin_user_id = conn.assigns.current_user_id
    limit = parse_int(params["limit"], 50, 200)

    case Finance.get_pending_purchases(admin_user_id, limit) do
      {:ok, requests} ->
        formatted_requests = Enum.map(requests, &format_purchase_request_response/1)
        conn |> json(formatted_requests)

      {:error, :access_denied} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Admin access required"})
    end
  end

  @doc """
  Approve purchase request (ADMIN ONLY)
  """
  def approve_purchase(conn, %{"requestId" => request_id} = params) do
    admin_user_id = conn.assigns.current_user_id
    admin_note = params["adminNote"]

    case Finance.approve_purchase_request(request_id, admin_note, admin_user_id) do
      {:ok, _request} ->
        conn |> json(%{message: "Purchase request approved and coins added"})

      {:error, :access_denied} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Admin access required"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to approve purchase", details: inspect(reason)})
    end
  end

  @doc """
  Reject purchase request (ADMIN ONLY)
  """
  def reject_purchase(conn, %{"requestId" => request_id} = params) do
    admin_user_id = conn.assigns.current_user_id
    admin_note = params["adminNote"]

    if is_nil(admin_note) or admin_note == "" do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Admin note is required for rejection"})
    else
      case Finance.reject_purchase_request(request_id, admin_note, admin_user_id) do
        {:ok, _request} ->
          conn |> json(%{message: "Purchase request rejected"})

        {:error, :access_denied} ->
          conn
          |> put_status(:forbidden)
          |> json(%{error: "Admin access required"})

        {:error, reason} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to reject purchase", details: inspect(reason)})
      end
    end
  end

  # Private helper functions

  defp format_wallet_response(wallet) do
    %{
      walletId: wallet.wallet_id,
      userId: wallet.user_id,
      userPhoneNumber: wallet.user_phone_number,
      userName: wallet.user_name,
      coinsBalance: wallet.coins_balance,
      createdAt: wallet.inserted_at,
      updatedAt: wallet.updated_at
    }
  end

  defp format_transaction_response(transaction) do
    %{
      transactionId: transaction.transaction_id,
      walletId: transaction.wallet_id,
      userId: transaction.user_id,
      type: transaction.type,
      coinAmount: transaction.coin_amount,
      balanceBefore: transaction.balance_before,
      balanceAfter: transaction.balance_after,
      description: transaction.description,
      referenceId: transaction.reference_id,
      adminNote: transaction.admin_note,
      paymentMethod: transaction.payment_method,
      paymentReference: transaction.payment_reference,
      packageId: transaction.package_id,
      paidAmount: transaction.paid_amount,
      metadata: transaction.metadata,
      createdAt: transaction.inserted_at
    }
  end

  defp format_purchase_request_response(request) do
    %{
      id: request.id,
      userId: request.user_id,
      packageId: request.package_id,
      coinAmount: request.coin_amount,
      paidAmount: request.paid_amount,
      paymentReference: request.payment_reference,
      paymentMethod: request.payment_method,
      status: request.status,
      requestedAt: request.requested_at,
      processedAt: request.processed_at,
      adminNote: request.admin_note
    }
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp parse_int(value, default, max \\ nil)
  defp parse_int(nil, default, _max), do: default
  defp parse_int(value, default, max) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 ->
        if max && int > max, do: max, else: int
      _ -> default
    end
  end
  defp parse_int(value, default, max) when is_integer(value) and value > 0 do
    if max && value > max, do: max, else: value
  end
  defp parse_int(_, default, _max), do: default

  defp is_admin?(%{user_type: "admin"}), do: true
  defp is_admin?(_), do: false
end
