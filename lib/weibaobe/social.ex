defmodule Weibaobe.Social do
  @moduledoc """
  The Social context for managing user follows and social interactions.
  """

  import Ecto.Query, warn: false
  alias Weibaobe.Repo
  alias Weibaobe.Social.UserFollow
  alias Weibaobe.Accounts.User

  @doc """
  Follows a user.
  """
  def follow_user(follower_id, following_id) do
    cond do
      follower_id == following_id ->
        {:error, :cannot_follow_self}

      user_following?(follower_id, following_id) ->
        {:error, :already_following}

      true ->
        %UserFollow{}
        |> UserFollow.changeset(%{follower_id: follower_id, following_id: following_id})
        |> Repo.insert()
        |> case do
          {:ok, _follow} -> {:ok, :followed}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Unfollows a user.
  """
  def unfollow_user(follower_id, following_id) do
    case Repo.get_by(UserFollow, follower_id: follower_id, following_id: following_id) do
      nil ->
        {:error, :not_following}

      follow ->
        case Repo.delete(follow) do
          {:ok, _} -> {:ok, :unfollowed}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Checks if a user is following another user.
  """
  def user_following?(follower_id, following_id) do
    UserFollow
    |> where([uf], uf.follower_id == ^follower_id and uf.following_id == ^following_id)
    |> Repo.exists?()
  end

  @doc """
  Gets users that follow a specific user (followers).
  """
  def get_user_followers(user_id, limit \\ 20, offset \\ 0) do
    from(u in User,
         join: uf in UserFollow, on: u.uid == uf.follower_id,
         where: uf.following_id == ^user_id and u.is_active == true,
         order_by: [desc: uf.inserted_at],
         limit: ^limit,
         offset: ^offset)
    |> Repo.all()
  end

  @doc """
  Gets users that a specific user is following (following).
  """
  def get_user_following(user_id, limit \\ 20, offset \\ 0) do
    from(u in User,
         join: uf in UserFollow, on: u.uid == uf.following_id,
         where: uf.follower_id == ^user_id and u.is_active == true,
         order_by: [desc: uf.inserted_at],
         limit: ^limit,
         offset: ^offset)
    |> Repo.all()
  end

  @doc """
  Gets follower count for a user.
  """
  def get_follower_count(user_id) do
    UserFollow
    |> where([uf], uf.following_id == ^user_id)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Gets following count for a user.
  """
  def get_following_count(user_id) do
    UserFollow
    |> where([uf], uf.follower_id == ^user_id)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Gets mutual followers between two users.
  """
  def get_mutual_followers(user1_id, user2_id) do
    # Users who follow both user1 and user2
    user1_followers = from(uf in UserFollow,
                          where: uf.following_id == ^user1_id,
                          select: uf.follower_id)

    user2_followers = from(uf in UserFollow,
                          where: uf.following_id == ^user2_id,
                          select: uf.follower_id)

    from(u in User,
         where: u.uid in subquery(user1_followers) and
                u.uid in subquery(user2_followers) and
                u.is_active == true,
         order_by: [desc: u.followers_count])
    |> Repo.all()
  end

  @doc """
  Gets mutual followers count between two users.
  """
  def get_mutual_followers_count(user1_id, user2_id) do
    user1_followers = from(uf in UserFollow,
                          where: uf.following_id == ^user1_id,
                          select: uf.follower_id)

    user2_followers = from(uf in UserFollow,
                          where: uf.following_id == ^user2_id,
                          select: uf.follower_id)

    from(uf1 in subquery(user1_followers),
         join: uf2 in subquery(user2_followers), on: uf1.follower_id == uf2.follower_id)
    |> Repo.aggregate(:count, :follower_id)
  end

  @doc """
  Gets users suggested for following (based on mutual connections).
  """
  def get_suggested_users(user_id, limit \\ 10) do
    # Users followed by people the current user follows
    # but not followed by the current user
    current_user_following = from(uf in UserFollow,
                                 where: uf.follower_id == ^user_id,
                                 select: uf.following_id)

    suggested_query = from(u in User,
                          join: uf1 in UserFollow, on: u.uid == uf1.following_id,
                          join: uf2 in UserFollow, on: uf1.follower_id == uf2.following_id,
                          where: uf2.follower_id == ^user_id and
                                u.uid != ^user_id and
                                u.uid not in subquery(current_user_following) and
                                u.is_active == true,
                          group_by: u.uid,
                          order_by: [desc: count(uf1.id), desc: u.followers_count],
                          limit: ^limit,
                          select: u)

    Repo.all(suggested_query)
  end

  @doc """
  Gets popular users for discovery (not followed by current user).
  """
  def get_discover_users(user_id, limit \\ 10) do
    current_user_following = if user_id do
      from(uf in UserFollow,
           where: uf.follower_id == ^user_id,
           select: uf.following_id)
    else
      from(uf in UserFollow, where: false, select: uf.following_id)
    end

    query = from(u in User,
                 where: u.is_active == true and
                        u.followers_count > 0,
                 order_by: [desc: u.followers_count, desc: u.is_verified, desc: u.inserted_at],
                 limit: ^limit)

    query = if user_id do
      where(query, [u], u.uid != ^user_id and u.uid not in subquery(current_user_following))
    else
      query
    end

    Repo.all(query)
  end

  @doc """
  Gets follow activity for a user's dashboard.
  """
  def get_follow_activity(user_id, limit \\ 20) do
    # Recent followers
    recent_followers = from(uf in UserFollow,
                           join: u in User, on: uf.follower_id == u.uid,
                           where: uf.following_id == ^user_id,
                           order_by: [desc: uf.inserted_at],
                           limit: ^limit,
                           select: %{
                             type: "new_follower",
                             user: u,
                             timestamp: uf.inserted_at
                           })

    Repo.all(recent_followers)
  end

  @doc """
  Bulk checks if current user is following a list of users.
  """
  def bulk_check_following(follower_id, user_ids) when is_list(user_ids) do
    following_ids = UserFollow
                   |> where([uf], uf.follower_id == ^follower_id and uf.following_id in ^user_ids)
                   |> select([uf], uf.following_id)
                   |> Repo.all()
                   |> MapSet.new()

    Map.new(user_ids, fn user_id ->
      {user_id, MapSet.member?(following_ids, user_id)}
    end)
  end

  @doc """
  Adds following status to a list of users for a specific follower.
  """
  def add_following_status_to_users(users, follower_id) when is_list(users) do
    user_ids = Enum.map(users, & &1.uid)
    following_map = bulk_check_following(follower_id, user_ids)

    Enum.map(users, fn user ->
      is_following = Map.get(following_map, user.uid, false)
      is_current_user = user.uid == follower_id

      %{user |
        is_following: is_following,
        is_current_user: is_current_user
      }
    end)
  end

  def add_following_status_to_users(users, _follower_id), do: users

  @doc """
  Gets social statistics for a user.
  """
  def get_user_social_stats(user_id) do
    followers_count = get_follower_count(user_id)
    following_count = get_following_count(user_id)

    # Get recent activity counts
    recent_followers_query = from(uf in UserFollow,
                                 where: uf.following_id == ^user_id and
                                        uf.inserted_at > ago(7, "day"),
                                 select: count(uf.id))

    recent_followers_count = Repo.one(recent_followers_query) || 0

    %{
      followers_count: followers_count,
      following_count: following_count,
      recent_followers_count: recent_followers_count
    }
  end

  @doc """
  Gets network growth analytics (admin only).
  """
  def get_network_growth_stats(user_id) do
    if is_admin?(user_id) do
      # Daily follow activity for the past 30 days
      daily_follows = from(uf in UserFollow,
                          where: uf.inserted_at > ago(30, "day"),
                          group_by: fragment("DATE(?)", uf.inserted_at),
                          order_by: [desc: fragment("DATE(?)", uf.inserted_at)],
                          select: %{
                            date: fragment("DATE(?)", uf.inserted_at),
                            follows_count: count(uf.id)
                          })

      # Most followed users
      top_users = from(u in User,
                      where: u.is_active == true and u.followers_count > 0,
                      order_by: [desc: u.followers_count],
                      limit: 10,
                      select: %{
                        uid: u.uid,
                        name: u.name,
                        followers_count: u.followers_count
                      })

      %{
        daily_follows: Repo.all(daily_follows),
        top_users: Repo.all(top_users)
      }
    else
      {:error, :access_denied}
    end
  end

  defp is_admin?(user_id) do
    case Weibaobe.Accounts.get_user(user_id) do
      {:ok, %{user_type: "admin"}} -> true
      _ -> false
    end
  end
end
