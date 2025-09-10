defmodule WeibaobeWeb.UserController do
  use WeibaobeWeb, :controller

  alias Weibaobe.Accounts
  alias Weibaobe.Social

  action_fallback WeibaobeWeb.FallbackController

  @doc """
  Get user by ID (PUBLIC)
  """
  def show(conn, %{"userId" => user_id}) do
    case Accounts.get_user(user_id) do
      {:ok, user} ->
        # Add following status if current user is authenticated
        current_user_id = conn.assigns[:current_user_id]

        formatted_user = user
                        |> format_user_response()
                        |> add_user_context(current_user_id, user_id)

        conn |> json(formatted_user)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})
    end
  end

  @doc """
  Update user profile (REQUIRES AUTH)
  """
  def update(conn, %{"userId" => user_id} = params) do
    requesting_user_id = conn.assigns.current_user_id

    # Verify user can update this profile
    cond do
      requesting_user_id == user_id ->
        update_user_profile(conn, user_id, params)

      is_admin?(conn.assigns.current_user) ->
        update_user_profile(conn, user_id, params)

      true ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied"})
    end
  end

  @doc """
  Delete user (REQUIRES AUTH)
  """
  def delete(conn, %{"userId" => user_id}) do
    requesting_user_id = conn.assigns.current_user_id

    cond do
      requesting_user_id == user_id ->
        delete_user_account(conn, user_id)

      is_admin?(conn.assigns.current_user) ->
        delete_user_account(conn, user_id)

      true ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied"})
    end
  end

  @doc """
  List all users with filtering (PUBLIC)
  """
  def index(conn, params) do
    limit = parse_int(params["limit"], 50, 1000)
    offset = parse_int(params["offset"], 0, nil)
    user_type = params["userType"]
    verified = parse_boolean(params["verified"])
    query = params["q"]

    opts = [
      limit: limit,
      offset: offset,
      user_type: user_type,
      verified: verified,
      query: query
    ]

    users = Accounts.list_users(opts)

    # Add context for current user if authenticated
    current_user_id = conn.assigns[:current_user_id]
    formatted_users = users
                     |> Enum.map(&format_user_response/1)
                     |> Social.add_following_status_to_users(current_user_id)

    conn
    |> json(%{
      users: formatted_users,
      total: length(users)
    })
  end

  @doc """
  Search users (PUBLIC)
  """
  def search(conn, %{"q" => query} = params) when is_binary(query) and query != "" do
    limit = parse_int(params["limit"], 20, 100)

    users = Accounts.search_users(query, limit)

    # Add context for current user if authenticated
    current_user_id = conn.assigns[:current_user_id]
    formatted_users = users
                     |> Enum.map(&format_user_response/1)
                     |> Social.add_following_status_to_users(current_user_id)

    conn
    |> json(%{
      users: formatted_users,
      total: length(users),
      query: query
    })
  end

  def search(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Search query required"})
  end

  @doc """
  Get user statistics (PUBLIC)
  """
  def stats(conn, %{"userId" => user_id}) do
    case Accounts.get_user_stats(user_id) do
      {:ok, stats} ->
        formatted_stats = %{
          user: format_user_response(stats.user),
          totalViews: stats.total_views,
          totalLikes: stats.total_likes,
          videosCount: stats.videos_count,
          followersCount: stats.followers_count,
          followingCount: stats.following_count,
          engagementRate: stats.engagement_rate,
          joinDate: stats.join_date,
          lastActiveDate: stats.last_active_date
        }

        conn |> json(formatted_stats)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})
    end
  end

  @doc """
  Update user status (ADMIN ONLY)
  """
  def update_status(conn, %{"userId" => user_id} = params) do
    case Accounts.get_user(user_id) do
      {:ok, user} ->
        status_attrs = %{}
        |> put_if_present("is_active", params["isActive"])
        |> put_if_present("is_verified", params["isVerified"])
        |> put_if_present("is_featured", params["isFeatured"])
        |> put_if_present("user_type", params["userType"])

        if map_size(status_attrs) == 0 do
          conn
          |> put_status(:bad_request)
          |> json(%{error: "No fields to update"})
        else
          case Accounts.update_user_status(user, status_attrs) do
            {:ok, _updated_user} ->
              conn |> json(%{message: "User status updated successfully"})

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{
                error: "Failed to update user status",
                details: format_changeset_errors(changeset)
              })
          end
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})
    end
  end

  # Private helper functions

  defp update_user_profile(conn, user_id, params) do
    case Accounts.get_user(user_id) do
      {:ok, user} ->
        update_attrs = %{}
        |> put_if_present("name", params["name"])
        |> put_if_present("profile_image", params["profileImage"])
        |> put_if_present("cover_image", params["coverImage"])
        |> put_if_present("bio", params["bio"])
        |> put_if_present("tags", params["tags"])

        case Accounts.update_user(user, update_attrs) do
          {:ok, updated_user} ->
            conn
            |> json(%{
              message: "User updated successfully",
              user: format_user_response(updated_user)
            })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: "Failed to update user",
              details: format_changeset_errors(changeset)
            })
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})
    end
  end

  defp delete_user_account(conn, user_id) do
    case Accounts.get_user(user_id) do
      {:ok, user} ->
        case Accounts.delete_user(user) do
          {:ok, :deleted} ->
            conn |> json(%{message: "User deleted successfully"})

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{
              error: "Failed to delete user",
              details: inspect(reason)
            })
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})
    end
  end

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
      lastSeen: user.last_seen,
      # Virtual fields (will be set by context functions)
      isFollowing: Map.get(user, :is_following, false),
      isCurrentUser: Map.get(user, :is_current_user, false)
    }
  end

  defp add_user_context(user_data, nil, _user_id), do: user_data
  defp add_user_context(user_data, current_user_id, user_id) do
    is_following = if current_user_id != user_id do
      Social.user_following?(current_user_id, user_id)
    else
      false
    end

    user_data
    |> Map.put(:isFollowing, is_following)
    |> Map.put(:isCurrentUser, current_user_id == user_id)
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

  defp parse_boolean(nil), do: nil
  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(true), do: true
  defp parse_boolean(false), do: false
  defp parse_boolean(_), do: nil

  defp put_if_present(map, key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  defp is_admin?(%{user_type: "admin"}), do: true
  defp is_admin?(_), do: false
end
