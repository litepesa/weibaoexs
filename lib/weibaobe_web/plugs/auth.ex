defmodule WeibaobeWeb.Plugs.Auth do
  @moduledoc """
  Authentication plugs for Firebase token verification
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Weibaobe.Services.FirebaseAuth
  alias Weibaobe.Accounts

  def init(opts), do: opts

  @doc """
  Verifies Firebase ID token and sets current user
  """
  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case FirebaseAuth.verify_id_token(token) do
          {:ok, claims} ->
            conn
            |> assign(:current_user_id, claims["uid"])
            |> assign(:firebase_claims, claims)

          {:error, _reason} ->
            conn
            |> put_status(:unauthorized)
            |> put_view(json: WeibaobeWeb.ErrorJSON)
            |> render(:error, %{message: "Invalid token"})
            |> halt()
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: WeibaobeWeb.ErrorJSON)
        |> render(:error, %{message: "Authorization header required"})
        |> halt()
    end
  end
end

defmodule WeibaobeWeb.Plugs.RequireAuth do
  @moduledoc """
  Ensures user is authenticated and exists in database
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Weibaobe.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_user_id] do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: WeibaobeWeb.ErrorJSON)
        |> render(:error, %{message: "User not authenticated"})
        |> halt()

      user_id ->
        case Accounts.get_user(user_id) do
          {:ok, user} ->
            conn
            |> assign(:current_user, user)

          {:error, :not_found} ->
            conn
            |> put_status(:unauthorized)
            |> put_view(json: WeibaobeWeb.ErrorJSON)
            |> render(:error, %{message: "User not found in database"})
            |> halt()

          {:error, _reason} ->
            conn
            |> put_status(:internal_server_error)
            |> put_view(json: WeibaobeWeb.ErrorJSON)
            |> render(:error, %{message: "Database error"})
            |> halt()
        end
    end
  end
end

defmodule WeibaobeWeb.Plugs.RequireAdmin do
  @moduledoc """
  Ensures current user has admin privileges
  """

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      %{user_type: "admin"} ->
        conn

      %{user_type: _other} ->
        conn
        |> put_status(:forbidden)
        |> put_view(json: WeibaobeWeb.ErrorJSON)
        |> render(:error, %{message: "Admin access required"})
        |> halt()

      nil ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: WeibaobeWeb.ErrorJSON)
        |> render(:error, %{message: "User not authenticated"})
        |> halt()
    end
  end
end

defmodule WeibaobeWeb.Plugs.RequireModerator do
  @moduledoc """
  Ensures current user has moderator or admin privileges
  """

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      %{user_type: type} when type in ["admin", "moderator"] ->
        conn

      %{user_type: _other} ->
        conn
        |> put_status(:forbidden)
        |> put_view(json: WeibaobeWeb.ErrorJSON)
        |> render(:error, %{message: "Moderator access required"})
        |> halt()

      nil ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: WeibaobeWeb.ErrorJSON)
        |> render(:error, %{message: "User not authenticated"})
        |> halt()
    end
  end
end

defmodule WeibaobeWeb.Plugs.LoadCurrentUser do
  @moduledoc """
  Optionally loads current user if token is present (for public endpoints that benefit from user context)
  """

  import Plug.Conn

  alias Weibaobe.Services.FirebaseAuth
  alias Weibaobe.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case FirebaseAuth.verify_id_token(token) do
          {:ok, claims} ->
            case Accounts.get_user(claims["uid"]) do
              {:ok, user} ->
                conn
                |> assign(:current_user_id, claims["uid"])
                |> assign(:current_user, user)
                |> assign(:firebase_claims, claims)

              {:error, _} ->
                conn
            end

          {:error, _} ->
            conn
        end

      _ ->
        conn
    end
  end
end
