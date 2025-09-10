defmodule Weibaobe.Accounts do
  @moduledoc """
  The Accounts context for managing users and authentication.
  """

  import Ecto.Query, warn: false
  alias Weibaobe.Repo
  alias Weibaobe.Accounts.User

  @doc """
  Gets a single user by UID.
  """
  def get_user(uid) when is_binary(uid) do
    case Repo.get(User, uid) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @doc """
  Gets a user by UID, raises if not found.
  """
  def get_user!(uid) do
    Repo.get!(User, uid)
  end

  @doc """
  Creates or updates a user (sync operation for Firebase integration).
  """
  def sync_user(attrs) do
    case get_user(attrs["uid"] || attrs[:uid]) do
      {:ok, user} ->
        # User exists, update last seen and basic info
        update_user_sync(user, attrs)

      {:error, :not_found} ->
        # User doesn't exist, create new
        create_user_sync(attrs)
    end
  end

  @doc """
  Creates a new user from sync data.
  """
  def create_user_sync(attrs) do
    %User{}
    |> User.sync_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, user} -> {:ok, user}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Updates user with sync data (last seen, basic profile updates).
  """
  def update_user_sync(user, attrs) do
    user
    |> User.update_last_seen()
    |> User.update_changeset(Map.take(attrs, ["name", "profile_image", "bio"]))
    |> Repo.update()
  end

  @doc """
  Updates a user's profile information.
  """
  def update_user(user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates user status (admin function).
  """
  def update_user_status(user, attrs) do
    user
    |> User.admin_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user and all associated data.
  """
  def delete_user(%User{} = user) do
    Repo.transaction(fn ->
      # Delete in reverse dependency order
      delete_user_dependencies(user.uid)
      Repo.delete!(user)
    end)
    |> case do
      {:ok, _} -> {:ok, :deleted}
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_user_dependencies(user_id) do
    # Delete user follows
    from(uf in Weibaobe.Social.UserFollow,
         where: uf.follower_id == ^user_id or uf.following_id == ^user_id)
    |> Repo.delete_all()

    # Delete comment likes (both user's likes and likes on user's comments)
    from(cl in Weibaobe.Content.CommentLike,
         where: cl.user_id == ^user_id or
                cl.comment_id in subquery(
                  from c in Weibaobe.Content.Comment,
                  where: c.author_id == ^user_id,
                  select: c.id
                ))
    |> Repo.delete_all()

    # Delete video likes
    from(vl in Weibaobe.Content.VideoLike, where: vl.user_id == ^user_id)
    |> Repo.delete_all()

    # Delete comments
    from(c in Weibaobe.Content.Comment, where: c.author_id == ^user_id)
    |> Repo.delete_all()

    # Delete videos
    from(v in Weibaobe.Content.Video, where: v.user_id == ^user_id)
    |> Repo.delete_all()

    # Delete wallet transactions
    from(wt in Weibaobe.Finance.WalletTransaction, where: wt.user_id == ^user_id)
    |> Repo.delete_all()

    # Delete wallet
    from(w in Weibaobe.Finance.Wallet, where: w.user_id == ^user_id)
    |> Repo.delete_all()

    # Delete coin purchase requests
    from(cpr in Weibaobe.Finance.CoinPurchaseRequest, where: cpr.user_id == ^user_id)
    |> Repo.delete_all()
  end

  @doc """
  Returns a list of users with optional filtering and pagination.
  """
  def list_users(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    user_type = Keyword.get(opts, :user_type)
    verified = Keyword.get(opts, :verified)
    query = Keyword.get(opts, :query)

    User
    |> where([u], u.is_active == true)
    |> filter_by_user_type(user_type)
    |> filter_by_verified(verified)
    |> filter_by_search(query)
    |> order_by([u], desc: u.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  defp filter_by_user_type(query, nil), do: query
  defp filter_by_user_type(query, user_type) do
    where(query, [u], u.user_type == ^user_type)
  end

  defp filter_by_verified(query, nil), do: query
  defp filter_by_verified(query, true) do
    where(query, [u], u.is_verified == true)
  end
  defp filter_by_verified(query, false) do
    where(query, [u], u.is_verified == false)
  end

  defp filter_by_search(query, nil), do: query
  defp filter_by_search(query, search_term) do
    search_pattern = "%#{search_term}%"
    where(query, [u],
          ilike(u.name, ^search_pattern) or
          ilike(u.phone_number, ^search_pattern)
    )
  end

  @doc """
  Searches for users by name or phone number.
  """
  def search_users(search_term, limit \\ 20) do
    search_pattern = "%#{search_term}%"

    User
    |> where([u], u.is_active == true)
    |> where([u],
         ilike(u.name, ^search_pattern) or
         ilike(u.phone_number, ^search_pattern) or
         ilike(u.bio, ^search_pattern)
       )
    |> order_by([u], [
         # Prioritize name matches first
         fragment("CASE WHEN ? ILIKE ? THEN 1 ELSE 2 END", u.name, ^search_pattern),
         desc: u.followers_count,
         desc: u.inserted_at
       ])
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets user statistics including engagement metrics.
  """
  def get_user_stats(user_id) do
    with {:ok, user} <- get_user(user_id) do
      # Get additional video stats
      video_stats_query = from v in Weibaobe.Content.Video,
                               where: v.user_id == ^user_id and v.is_active == true,
                               select: %{
                                 total_views: coalesce(sum(v.views_count), 0),
                                 total_likes: coalesce(sum(v.likes_count), 0)
                               }

      video_stats = Repo.one(video_stats_query) || %{total_views: 0, total_likes: 0}

      stats = %{
        user: user,
        total_views: video_stats.total_views,
        total_likes: video_stats.total_likes,
        videos_count: user.videos_count,
        followers_count: user.followers_count,
        following_count: user.following_count,
        engagement_rate: User.engagement_rate(user),
        join_date: user.inserted_at,
        last_active_date: user.last_seen
      }

      {:ok, stats}
    end
  end

  @doc """
  Updates last seen timestamp for a user.
  """
  def update_last_seen(user_id) when is_binary(user_id) do
    case get_user(user_id) do
      {:ok, user} ->
        user
        |> User.update_last_seen()
        |> Repo.update()

      error -> error
    end
  end

  def update_last_seen(%User{} = user) do
    user
    |> User.update_last_seen()
    |> Repo.update()
  end

  @doc """
  Gets users by their UIDs (batch operation).
  """
  def get_users_by_ids(user_ids) when is_list(user_ids) do
    User
    |> where([u], u.uid in ^user_ids)
    |> Repo.all()
    |> Enum.group_by(& &1.uid)
    |> Map.new(fn {uid, [user]} -> {uid, user} end)
  end

  @doc """
  Checks if a user exists by UID.
  """
  def user_exists?(user_id) do
    User
    |> where([u], u.uid == ^user_id)
    |> Repo.exists?()
  end

  @doc """
  Gets featured users (verified or popular users).
  """
  def get_featured_users(limit \\ 10) do
    User
    |> where([u], u.is_active == true)
    |> where([u], u.is_featured == true or u.is_verified == true)
    |> order_by([u], [desc: u.is_featured, desc: u.followers_count, desc: u.inserted_at])
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets users with the most followers.
  """
  def get_popular_users(limit \\ 10) do
    User
    |> where([u], u.is_active == true)
    |> where([u], u.followers_count > 0)
    |> order_by([u], [desc: u.followers_count, desc: u.inserted_at])
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Validates user data for creation.
  """
  def validate_user_creation(attrs) do
    case User.valid_for_creation?(attrs) do
      true -> :ok
      false -> {:error, User.creation_errors(attrs)}
    end
  end
end
