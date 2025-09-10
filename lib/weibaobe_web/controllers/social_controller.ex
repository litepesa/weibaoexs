defmodule WeibaobeWeb.SocialController do
  use WeibaobeWeb, :controller

  alias Weibaobe.Social

  action_fallback WeibaobeWeb.FallbackController

  @doc """
  Follow a user (REQUIRES AUTH)
  """
  def follow_user(conn, %{"userId" => target_user_id}) do
    user_id = conn.assigns.current_user_id

    case Social.follow_user(user_id, target_user_id) do
      {:ok, :followed} ->
        conn |> json(%{message: "User followed successfully"})

      {:error, :cannot_follow_self} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Cannot follow yourself"})

      {:error, :already_following} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Already following this user"})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to follow user"})
    end
  end

  @doc """
  Unfollow a user (REQUIRES AUTH)
  """
  def unfollow_user(conn, %{"userId" => target_user_id}) do
    user_id = conn.assigns.current_user_id

    case Social.unfollow_user(user_id, target_user_id) do
      {:ok, :unfollowed} ->
        conn |> json(%{message: "User unfollowed successfully"})

      {:error, :not_following} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Not following this user"})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to unfollow user"})
    end
  end

  @doc """
  Get user's followers (PUBLIC)
  """
  def get_followers(conn, %{"userId" => user_id} = params) do
    limit = parse_int(params["limit"], 20, 100)
    offset = parse_int(params["offset"], 0, nil)

    followers = Social.get_user_followers(user_id, limit, offset)
    current_user_id = conn.assigns[:current_user_id]

    formatted_followers = followers
                         |> Social.add_following_status_to_users(current_user_id)
                         |> Enum.map(&format_user_response/1)

    conn
    |> json(%{
      users: formatted_followers,
      total: length(formatted_followers)
    })
  end

  @doc """
  Get users that a user is following (PUBLIC)
  """
  def get_following(conn, %{"userId" => user_id} = params) do
    limit = parse_int(params["limit"], 20, 100)
    offset = parse_int(params["offset"], 0, nil)

    following = Social.get_user_following(user_id, limit, offset)
    current_user_id = conn.assigns[:current_user_id]

    formatted_following = following
                         |> Social.add_following_status_to_users(current_user_id)
                         |> Enum.map(&format_user_response/1)

    conn
    |> json(%{
      users: formatted_following,
      total: length(formatted_following)
    })
  end

  @doc """
  Get mutual followers between current user and another user (REQUIRES AUTH)
  """
  def get_mutual_followers(conn, %{"userId" => user_id}) do
    current_user_id = conn.assigns.current_user_id

    if current_user_id == user_id do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Cannot get mutual followers with yourself"})
    else
      mutual_followers = Social.get_mutual_followers(current_user_id, user_id)

      formatted_followers = mutual_followers
                           |> Social.add_following_status_to_users(current_user_id)
                           |> Enum.map(&format_user_response/1)

      conn
      |> json(%{
        users: formatted_followers,
        total: length(formatted_followers),
        mutualWith: user_id
      })
    end
  end

  @doc """
  Get mutual followers count between current user and another user (REQUIRES AUTH)
  """
  def get_mutual_followers_count(conn, %{"userId" => user_id}) do
    current_user_id = conn.assigns.current_user_id

    if current_user_id == user_id do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Cannot get mutual followers with yourself"})
    else
      count = Social.get_mutual_followers_count(current_user_id, user_id)

      conn
      |> json(%{
        mutualFollowersCount: count,
        userId: user_id
      })
    end
  end

  @doc """
  Get suggested users to follow (REQUIRES AUTH)
  """
  def get_suggested_users(conn, params) do
    user_id = conn.assigns.current_user_id
    limit = parse_int(params["limit"], 10, 20)

    suggested_users = Social.get_suggested_users(user_id, limit)

    formatted_users = suggested_users
                     |> Social.add_following_status_to_users(user_id)
                     |> Enum.map(&format_user_response/1)

    conn
    |> json(%{
      users: formatted_users,
      total: length(formatted_users),
      type: "suggested"
    })
  end

  @doc """
  Get users for discovery (PUBLIC)
  """
  def get_discover_users(conn, params) do
    current_user_id = conn.assigns[:current_user_id]
    limit = parse_int(params["limit"], 10, 20)

    discover_users = Social.get_discover_users(current_user_id, limit)

    formatted_users = discover_users
                     |> Social.add_following_status_to_users(current_user_id)
                     |> Enum.map(&format_user_response/1)

    conn
    |> json(%{
      users: formatted_users,
      total: length(formatted_users),
      type: "discover"
    })
  end

  @doc """
  Get follow activity for current user (REQUIRES AUTH)
  """
  def get_follow_activity(conn, params) do
    user_id = conn.assigns.current_user_id
    limit = parse_int(params["limit"], 20, 50)

    activity = Social.get_follow_activity(user_id, limit)

    formatted_activity = Enum.map(activity, fn activity_item ->
      %{
        type: activity_item.type,
        user: format_user_response(activity_item.user),
        timestamp: activity_item.timestamp
      }
    end)

    conn
    |> json(%{
      activity: formatted_activity,
      total: length(formatted_activity)
    })
  end

  @doc """
  Get social statistics for a user (PUBLIC)
  """
  def get_user_social_stats(conn, %{"userId" => user_id}) do
    stats = Social.get_user_social_stats(user_id)

    conn
    |> json(%{
      userId: user_id,
      followersCount: stats.followers_count,
      followingCount: stats.following_count,
      recentFollowersCount: stats.recent_followers_count
    })
  end

  @doc """
  Check if current user is following a specific user (REQUIRES AUTH)
  """
  def check_following(conn, %{"userId" => target_user_id}) do
    current_user_id = conn.assigns.current_user_id

    is_following = Social.user_following?(current_user_id, target_user_id)

    conn
    |> json(%{
      userId: target_user_id,
      isFollowing: is_following
    })
  end

  @doc """
  Check if current user is following a list of users (REQUIRES AUTH)
  """
  def bulk_check_following(conn, %{"userIds" => user_ids}) when is_list(user_ids) do
    current_user_id = conn.assigns.current_user_id

    following_map = Social.bulk_check_following(current_user_id, user_ids)

    conn
    |> json(%{
      following: following_map,
      totalChecked: length(user_ids)
    })
  end

  def bulk_check_following(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "userIds array is required"})
  end

  @doc """
  Get featured users for discovery (PUBLIC)
  """
  def get_featured_users(conn, params) do
    limit = parse_int(params["limit"], 10, 50)
    current_user_id = conn.assigns[:current_user_id]

    # Get featured users from Accounts context
    featured_users = Weibaobe.Accounts.get_featured_users(limit)

    formatted_users = featured_users
                     |> Social.add_following_status_to_users(current_user_id)
                     |> Enum.map(&format_user_response/1)

    conn
    |> json(%{
      users: formatted_users,
      total: length(formatted_users),
      type: "featured"
    })
  end

  @doc """
  Get popular users (PUBLIC)
  """
  def get_popular_users(conn, params) do
    limit = parse_int(params["limit"], 10, 50)
    current_user_id = conn.assigns[:current_user_id]

    # Get popular users from Accounts context
    popular_users = Weibaobe.Accounts.get_popular_users(limit)

    formatted_users = popular_users
                     |> Social.add_following_status_to_users(current_user_id)
                     |> Enum.map(&format_user_response/1)

    conn
    |> json(%{
      users: formatted_users,
      total: length(formatted_users),
      type: "popular"
    })
  end

  @doc """
  Get following status for multiple users (REQUIRES AUTH)
  """
  def get_following_status(conn, %{"userIds" => user_ids}) when is_list(user_ids) do
    current_user_id = conn.assigns.current_user_id

    # Limit batch size to prevent abuse
    if length(user_ids) > 100 do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Too many user IDs. Maximum 100 allowed"})
    else
      following_status = Social.bulk_check_following(current_user_id, user_ids)

      # Format response with user details
      user_status_list = Enum.map(user_ids, fn user_id ->
        %{
          userId: user_id,
          isFollowing: Map.get(following_status, user_id, false)
        }
      end)

      conn
      |> json(%{
        users: user_status_list,
        totalChecked: length(user_ids)
      })
    end
  end

  def get_following_status(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "userIds array is required"})
  end

  @doc """
  Get network growth statistics (ADMIN ONLY)
  """
  def get_network_stats(conn, _params) do
    user_id = conn.assigns.current_user_id

    case Social.get_network_growth_stats(user_id) do
      {:ok, stats} ->
        formatted_stats = %{
          dailyFollows: stats.daily_follows,
          topUsers: stats.top_users,
          generatedAt: DateTime.utc_now()
        }

        conn |> json(formatted_stats)

      {:error, :access_denied} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Admin access required"})
    end
  end

  @doc """
  Get comprehensive social analytics (ADMIN ONLY)
  """
  def get_social_analytics(conn, params) do
    user_id = conn.assigns.current_user_id

    case Social.get_network_growth_stats(user_id) do
      {:ok, network_stats} ->
        # Additional analytics
        days = parse_int(params["days"], 30, 365)

        analytics = %{
          networkGrowth: network_stats,
          timeframe: "#{days} days",
          generatedAt: DateTime.utc_now(),
          summary: %{
            totalFollows: length(network_stats.daily_follows),
            topUserCount: length(network_stats.top_users),
            avgDailyFollows: calculate_avg_daily_follows(network_stats.daily_follows)
          }
        }

        conn |> json(analytics)

      {:error, :access_denied} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Admin access required"})
    end
  end

  @doc """
  Export user connections (ADMIN ONLY)
  """
  def export_connections(conn, %{"userId" => user_id} = params) do
    admin_user_id = conn.assigns.current_user_id

    if is_admin?(conn.assigns.current_user) do
      include_followers = params["includeFollowers"] == "true"
      include_following = params["includeFollowing"] == "true"

      export_data = %{
        userId: user_id,
        exportedAt: DateTime.utc_now(),
        data: %{}
      }

      export_data = if include_followers do
        followers = Social.get_user_followers(user_id, 1000, 0)
        put_in(export_data.data.followers, Enum.map(followers, &minimal_user_format/1))
      else
        export_data
      end

      export_data = if include_following do
        following = Social.get_user_following(user_id, 1000, 0)
        put_in(export_data.data.following, Enum.map(following, &minimal_user_format/1))
      else
        export_data
      end

      conn |> json(export_data)
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Admin access required"})
    end
  end

  def export_connections(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "userId is required"})
  end

  # Private helper functions

  defp format_user_response(user) do
    %{
      uid: user.uid,
      name: user.name,
      phoneNumber: user.phone_number,
      profileImage: user.profile_image,
      bio: user.bio,
      userType: user.user_type,
      followersCount: user.followers_count,
      followingCount: user.following_count,
      videosCount: user.videos_count,
      isVerified: user.is_verified,
      isActive: user.is_active,
      isFeatured: user.is_featured,
      tags: user.tags,
      createdAt: user.inserted_at,
      # Virtual fields
      isFollowing: Map.get(user, :is_following, false),
      isCurrentUser: Map.get(user, :is_current_user, false)
    }
  end

  defp minimal_user_format(user) do
    %{
      uid: user.uid,
      name: user.name,
      phoneNumber: user.phone_number,
      profileImage: user.profile_image,
      followersCount: user.followers_count,
      isVerified: user.is_verified
    }
  end

  defp calculate_avg_daily_follows([]), do: 0
  defp calculate_avg_daily_follows(daily_follows) do
    total_follows = Enum.reduce(daily_follows, 0, fn day, acc ->
      acc + day.follows_count
    end)

    Float.round(total_follows / length(daily_follows), 2)
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
