defmodule WeibaobeWeb.FallbackController do
  @moduledoc """
  Fallback controller for handling common error scenarios
  """

  use WeibaobeWeb, :controller

  # Handle Ecto changeset errors
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: "Validation failed",
      details: format_changeset_errors(changeset)
    })
  end

  # Handle not found errors
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "Resource not found"})
  end

  # Handle access denied errors
  def call(conn, {:error, :access_denied}) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: "Access denied"})
  end

  # Handle unauthorized errors
  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "Authentication required"})
  end

  # Handle generic errors
  def call(conn, {:error, reason}) when is_atom(reason) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: format_error_reason(reason)})
  end

  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: reason})
  end

  # Handle unexpected errors
  def call(conn, error) do
    require Logger
    Logger.error("Unhandled error in fallback controller: #{inspect(error)}")

    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "Internal server error"})
  end

  # Private helper functions

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp format_error_reason(:already_liked), do: "Already liked"
  defp format_error_reason(:not_liked), do: "Not liked"
  defp format_error_reason(:already_following), do: "Already following"
  defp format_error_reason(:not_following), do: "Not following"
  defp format_error_reason(:cannot_follow_self), do: "Cannot follow yourself"
  defp format_error_reason(:insufficient_balance), do: "Insufficient balance"
  defp format_error_reason(:invalid_package), do: "Invalid package"
  defp format_error_reason(:invalid_token), do: "Invalid token"
  defp format_error_reason(reason), do: reason |> to_string() |> String.replace("_", " ") |> String.capitalize()
end

defmodule WeibaobeWeb.HealthController do
  use WeibaobeWeb, :controller

  alias Weibaobe.Services.{FirebaseAuth, R2Storage}

  def health(conn, _params) do
    # Check database health
    database_status = check_database()

    # Check Firebase health
    firebase_status = check_firebase()

    # Check R2 storage health
    storage_status = check_storage()

    overall_status = if database_status == :healthy and firebase_status == :healthy and storage_status == :healthy do
      :healthy
    else
      :unhealthy
    end

    status_code = if overall_status == :healthy, do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(%{
      status: overall_status,
      database: database_status,
      firebase: firebase_status,
      storage: storage_status,
      app: "video-social-media-phoenix",
      version: "1.0.0",
      timestamp: System.system_time(:second)
    })
  end

  # Private health check functions

  defp check_database do
    try do
      case Weibaobe.Repo.query("SELECT 1", []) do
        {:ok, _} -> :healthy
        {:error, _} -> :unhealthy
      end
    rescue
      _ -> :unhealthy
    end
  end

  defp check_firebase do
    case FirebaseAuth.health_check() do
      {:ok, :healthy} -> :healthy
      {:error, _} -> :unhealthy
    end
  end

  defp check_storage do
    case R2Storage.health_check() do
      {:ok, :healthy} -> :healthy
      {:error, _} -> :unhealthy
    end
  end
end
