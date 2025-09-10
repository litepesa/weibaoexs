defmodule WeibaobeWeb.AuthController do
  use WeibaobeWeb, :controller

  alias Weibaobe.Accounts
  alias Weibaobe.Services.FirebaseAuth

  action_fallback WeibaobeWeb.FallbackController

  @doc """
  Sync user endpoint (NO AUTH REQUIRED) - Solves chicken-and-egg problem
  This endpoint allows user creation BEFORE authentication check
  """
  def sync_user(conn, params) do
    # Extract user data from request body
    user_data = %{
      "uid" => params["uid"],
      "name" => params["name"] || "User",
      "phone_number" => params["phoneNumber"],
      "profile_image" => params["profileImage"] || "",
      "bio" => params["bio"] || ""
    }

    # Validate required fields
    cond do
      is_nil(user_data["uid"]) or user_data["uid"] == "" ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "UID is required"})

      is_nil(user_data["phone_number"]) or user_data["phone_number"] == "" ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Phone number is required"})

      true ->
        case Accounts.sync_user(user_data) do
          {:ok, user} ->
            conn
            |> put_status(:ok)
            |> json(%{
              message: "User synced successfully",
              user: format_user_response(user)
            })

          {:error, changeset} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{
              error: "Failed to sync user",
              details: format_changeset_errors(changeset)
            })
        end
    end
  end

  @doc """
  Verify Firebase token endpoint (NO AUTH REQUIRED)
  Manual token verification for debugging
  """
  def verify_token(conn, %{"token" => token}) when is_binary(token) do
    case FirebaseAuth.verify_id_token(token) do
      {:ok, claims} ->
        conn
        |> json(%{
          valid: true,
          claims: %{
            uid: claims["uid"],
            email: claims["email"],
            phone_number: claims["phone_number"],
            name: claims["name"],
            email_verified: claims["email_verified"],
            auth_time: claims["auth_time"],
            exp: claims["exp"]
          }
        })

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          valid: false,
          error: "Invalid token",
          reason: inspect(reason)
        })
    end
  end

  def verify_token(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Token is required"})
  end

  @doc """
  Get current authenticated user info (REQUIRES AUTH)
  """
  def get_current_user(conn, _params) do
    user = conn.assigns.current_user

    # Update last seen
    Accounts.update_last_seen(user)

    conn
    |> json(%{
      user: format_user_response(user)
    })
  end

  @doc """
  Profile sync with token validation (REQUIRES AUTH)
  Alternative sync for existing authenticated users
  """
  def sync_user_with_token(conn, params) do
    user_id = conn.assigns.current_user_id
    firebase_claims = conn.assigns.firebase_claims

    # Get Firebase user record if needed
    case FirebaseAuth.get_user(user_id) do
      {:ok, firebase_user} ->
        # Create user data from Firebase
        user_data = %{
          "uid" => user_id,
          "name" => get_display_name(firebase_user, params),
          "phone_number" => firebase_user["phone_number"],
          "profile_image" => params["profileImage"] || "",
          "bio" => params["bio"] || ""
        }

        case Accounts.sync_user(user_data) do
          {:ok, user} ->
            conn
            |> json(%{
              message: "User profile synced successfully",
              user: format_user_response(user)
            })

          {:error, changeset} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{
              error: "Failed to sync user profile",
              details: format_changeset_errors(changeset)
            })
        end

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to get Firebase user information"})
    end
  end

  # Private helper functions

  defp format_user_response(user) do
    %{
      uid: user.uid,
      name: user.name,
      phoneNumber: user.phone_number,
      profileImage: user.profile_image,
      coverImage: user.cover_image,
      bio: user.bio,
      userType: user.user_type,
      followersCount: user.followers_count,
      followingCount: user.following_count,
      videosCount: user.videos_count,
      likesCount: user.likes_count,
      isVerified: user.is_verified,
      isActive: user.is_active,
      isFeatured: user.is_featured,
      tags: user.tags,
      createdAt: user.inserted_at,
      updatedAt: user.updated_at,
      lastSeen: user.last_seen
    }
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp get_display_name(firebase_user, params) do
    cond do
      params["name"] && params["name"] != "" -> params["name"]
      firebase_user["display_name"] && firebase_user["display_name"] != "" -> firebase_user["display_name"]
      true -> "User"
    end
  end
end
