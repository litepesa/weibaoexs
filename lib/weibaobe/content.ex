defmodule Weibaobe.Content do
  @moduledoc """
  The Content context for managing videos, comments, and interactions.
  """

  import Ecto.Query, warn: false
  alias Weibaobe.Repo
  alias Weibaobe.Content.{Video, Comment, VideoLike, CommentLike}

  # ===============================
  # VIDEO OPERATIONS
  # ===============================

  @doc """
  Gets a single video by ID.
  """
  def get_video(id) do
    case Repo.get(Video, id) do
      nil -> {:error, :not_found}
      video -> {:ok, video}
    end
  end

  @doc """
  Gets a video and increments view count.
  """
  def get_video_and_increment_views(id) do
    case get_video(id) do
      {:ok, video} ->
        # Increment views asynchronously
        Task.start(fn -> increment_video_views(id) end)
        {:ok, video}

      error -> error
    end
  end

  @doc """
  Lists videos with filtering and pagination.
  """
  def list_videos(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    user_id = Keyword.get(opts, :user_id)
    featured = Keyword.get(opts, :featured)
    media_type = Keyword.get(opts, :media_type)
    sort_by = Keyword.get(opts, :sort_by, "latest")
    search_query = Keyword.get(opts, :query)

    Video
    |> where([v], v.is_active == true)
    |> filter_by_user(user_id)
    |> filter_by_featured(featured)
    |> filter_by_media_type(media_type)
    |> filter_by_search(search_query)
    |> apply_sort(sort_by)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  defp filter_by_user(query, nil), do: query
  defp filter_by_user(query, user_id) do
    where(query, [v], v.user_id == ^user_id)
  end

  defp filter_by_featured(query, nil), do: query
  defp filter_by_featured(query, featured) do
    where(query, [v], v.is_featured == ^featured)
  end

  defp filter_by_media_type(query, nil), do: query
  defp filter_by_media_type(query, "all"), do: query
  defp filter_by_media_type(query, "image") do
    where(query, [v], v.is_multiple_images == true)
  end
  defp filter_by_media_type(query, "video") do
    where(query, [v], v.is_multiple_images == false)
  end

  defp filter_by_search(query, nil), do: query
  defp filter_by_search(query, search_term) do
    search_pattern = "%#{search_term}%"
    where(query, [v],
          ilike(v.caption, ^search_pattern) or
          ilike(v.user_name, ^search_pattern)
    )
  end

  defp apply_sort(query, "latest") do
    order_by(query, [v], desc: v.inserted_at)
  end
  defp apply_sort(query, "popular") do
    order_by(query, [v], [desc: v.likes_count, desc: v.views_count, desc: v.inserted_at])
  end
  defp apply_sort(query, "trending") do
    # Trending algorithm: engagement score divided by time decay
    order_by(query, [v], desc: fragment("""
      (? * 2 + ? * 3 + ? * 5 + ?) /
      GREATEST(1, EXTRACT(EPOCH FROM (NOW() - ?)) / 3600)
      """, v.likes_count, v.comments_count, v.shares_count, v.views_count, v.inserted_at))
  end
  defp apply_sort(query, "views") do
    order_by(query, [v], [desc: v.views_count, desc: v.inserted_at])
  end
  defp apply_sort(query, "likes") do
    order_by(query, [v], [desc: v.likes_count, desc: v.inserted_at])
  end
  defp apply_sort(query, _), do: apply_sort(query, "latest")

  @doc """
  Gets featured videos.
  """
  def get_featured_videos(limit \\ 10) do
    Video
    |> where([v], v.is_active == true and v.is_featured == true)
    |> order_by([v], desc: v.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets trending videos.
  """
  def get_trending_videos(limit \\ 10) do
    list_videos(limit: limit, sort_by: "trending")
  end

  @doc """
  Gets videos for a specific user.
  """
  def get_user_videos(user_id, limit \\ 20, offset \\ 0) do
    list_videos(user_id: user_id, limit: limit, offset: offset)
  end

  @doc """
  Creates a video.
  """
  def create_video(attrs) do
    %Video{}
    |> Video.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a video (only owner or admin can update).
  """
  def update_video(%Video{} = video, attrs, user_id) do
    if video.user_id == user_id or is_admin?(user_id) do
      video
      |> Video.update_changeset(attrs)
      |> Repo.update()
    else
      {:error, :access_denied}
    end
  end

  @doc """
  Deletes a video and all associated data.
  """
  def delete_video(%Video{} = video, user_id) do
    if video.user_id == user_id or is_admin?(user_id) do
      Repo.transaction(fn ->
        delete_video_dependencies(video.id)
        Repo.delete!(video)
      end)
      |> case do
        {:ok, _} -> {:ok, :deleted}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :access_denied}
    end
  end

  def delete_video(video_id, user_id) when is_binary(video_id) do
    case get_video(video_id) do
      {:ok, video} -> delete_video(video, user_id)
      error -> error
    end
  end

  defp delete_video_dependencies(video_id) do
    # Delete video likes
    from(vl in VideoLike, where: vl.video_id == ^video_id)
    |> Repo.delete_all()

    # Delete comment likes for this video's comments
    from(cl in CommentLike,
         where: cl.comment_id in subquery(
           from c in Comment, where: c.video_id == ^video_id, select: c.id
         ))
    |> Repo.delete_all()

    # Delete comments
    from(c in Comment, where: c.video_id == ^video_id)
    |> Repo.delete_all()
  end

  @doc """
  Increments video view count.
  """
  def increment_video_views(video_id) do
    from(v in Video, where: v.id == ^video_id and v.is_active == true)
    |> Repo.update_all(inc: [views_count: 1], set: [updated_at: DateTime.utc_now()])
  end

  @doc """
  Increments video share count.
  """
  def increment_video_shares(video_id) do
    from(v in Video, where: v.id == ^video_id and v.is_active == true)
    |> Repo.update_all(inc: [shares_count: 1], set: [updated_at: DateTime.utc_now()])
  end

  # ===============================
  # VIDEO LIKE OPERATIONS
  # ===============================

  @doc """
  Likes a video.
  """
  def like_video(video_id, user_id) do
    case Repo.get_by(VideoLike, video_id: video_id, user_id: user_id) do
      nil ->
        %VideoLike{}
        |> VideoLike.changeset(%{video_id: video_id, user_id: user_id})
        |> Repo.insert()
        |> case do
          {:ok, _like} -> {:ok, :liked}
          {:error, changeset} -> {:error, changeset}
        end

      _existing_like ->
        {:error, :already_liked}
    end
  end

  @doc """
  Unlikes a video.
  """
  def unlike_video(video_id, user_id) do
    case Repo.get_by(VideoLike, video_id: video_id, user_id: user_id) do
      nil ->
        {:error, :not_liked}

      like ->
        case Repo.delete(like) do
          {:ok, _} -> {:ok, :unliked}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Checks if user has liked a video.
  """
  def video_liked?(video_id, user_id) do
    VideoLike
    |> where([vl], vl.video_id == ^video_id and vl.user_id == ^user_id)
    |> Repo.exists?()
  end

  @doc """
  Gets videos liked by a user.
  """
  def get_user_liked_videos(user_id, limit \\ 20, offset \\ 0) do
    from(v in Video,
         join: vl in VideoLike, on: v.id == vl.video_id,
         where: vl.user_id == ^user_id and v.is_active == true,
         order_by: [desc: vl.inserted_at],
         limit: ^limit,
         offset: ^offset)
    |> Repo.all()
  end

  # ===============================
  # COMMENT OPERATIONS
  # ===============================

  @doc """
  Gets comments for a video.
  """
  def get_video_comments(video_id, limit \\ 20, offset \\ 0) do
    Comment
    |> where([c], c.video_id == ^video_id)
    |> order_by([c], desc: c.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Creates a comment.
  """
  def create_comment(attrs) do
    %Comment{}
    |> Comment.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes a comment (only author or moderator can delete).
  """
  def delete_comment(comment_id, user_id) do
    case Repo.get(Comment, comment_id) do
      nil ->
        {:error, :not_found}

      %Comment{author_id: ^user_id} = comment ->
        delete_comment_with_dependencies(comment)

      comment ->
        if is_moderator?(user_id) do
          delete_comment_with_dependencies(comment)
        else
          {:error, :access_denied}
        end
    end
  end

  defp delete_comment_with_dependencies(%Comment{} = comment) do
    Repo.transaction(fn ->
      # Delete comment likes
      from(cl in CommentLike, where: cl.comment_id == ^comment.id)
      |> Repo.delete_all()

      # Delete replies to this comment
      from(c in Comment, where: c.replied_to_comment_id == ^comment.id)
      |> Repo.delete_all()

      # Delete the comment
      Repo.delete!(comment)
    end)
    |> case do
      {:ok, _} -> {:ok, :deleted}
      {:error, reason} -> {:error, reason}
    end
  end

  # ===============================
  # COMMENT LIKE OPERATIONS
  # ===============================

  @doc """
  Likes a comment.
  """
  def like_comment(comment_id, user_id) do
    case Repo.get_by(CommentLike, comment_id: comment_id, user_id: user_id) do
      nil ->
        %CommentLike{}
        |> CommentLike.changeset(%{comment_id: comment_id, user_id: user_id})
        |> Repo.insert()
        |> case do
          {:ok, _like} -> {:ok, :liked}
          {:error, changeset} -> {:error, changeset}
        end

      _existing_like ->
        {:error, :already_liked}
    end
  end

  @doc """
  Unlikes a comment.
  """
  def unlike_comment(comment_id, user_id) do
    case Repo.get_by(CommentLike, comment_id: comment_id, user_id: user_id) do
      nil ->
        {:error, :not_liked}

      like ->
        case Repo.delete(like) do
          {:ok, _} -> {:ok, :unliked}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Checks if user has liked a comment.
  """
  def comment_liked?(comment_id, user_id) do
    CommentLike
    |> where([cl], cl.comment_id == ^comment_id and cl.user_id == ^user_id)
    |> Repo.exists?()
  end

  # ===============================
  # ADMIN OPERATIONS
  # ===============================

  @doc """
  Toggles featured status of a video (admin only).
  """
  def toggle_video_featured(video_id, is_featured, user_id) do
    if is_admin?(user_id) do
      from(v in Video, where: v.id == ^video_id)
      |> Repo.update_all(set: [is_featured: is_featured, updated_at: DateTime.utc_now()])
      |> case do
        {1, _} -> {:ok, :updated}
        {0, _} -> {:error, :not_found}
      end
    else
      {:error, :access_denied}
    end
  end

  @doc """
  Toggles active status of a video (admin only).
  """
  def toggle_video_active(video_id, is_active, user_id) do
    if is_admin?(user_id) do
      from(v in Video, where: v.id == ^video_id)
      |> Repo.update_all(set: [is_active: is_active, updated_at: DateTime.utc_now()])
      |> case do
        {1, _} -> {:ok, :updated}
        {0, _} -> {:error, :not_found}
      end
    else
      {:error, :access_denied}
    end
  end

  # ===============================
  # SOCIAL FEED OPERATIONS
  # ===============================

  @doc """
  Gets video feed for users that current user follows.
  """
  def get_following_feed(user_id, limit \\ 20, offset \\ 0) do
    from(v in Video,
         join: uf in Weibaobe.Social.UserFollow, on: v.user_id == uf.following_id,
         where: uf.follower_id == ^user_id and v.is_active == true,
         order_by: [desc: v.inserted_at],
         limit: ^limit,
         offset: ^offset)
    |> Repo.all()
  end

  # ===============================
  # STATISTICS AND ANALYTICS
  # ===============================

  @doc """
  Gets video performance statistics for a user.
  """
  def get_user_video_stats(user_id) do
    from(v in Video,
         where: v.user_id == ^user_id and v.is_active == true,
         select: %{
           video_id: v.id,
           title: v.caption,
           likes_count: v.likes_count,
           comments_count: v.comments_count,
           views_count: v.views_count,
           shares_count: v.shares_count,
           created_at: v.inserted_at
         },
         order_by: [desc: v.inserted_at])
    |> Repo.all()
    |> Enum.map(fn stat ->
      engagement_rate = if stat.views_count > 0 do
        total_engagement = stat.likes_count + stat.comments_count + stat.shares_count
        (total_engagement / stat.views_count) * 100
      else
        0.0
      end

      Map.put(stat, :engagement_rate, engagement_rate)
    end)
  end

  @doc """
  Gets platform-wide video statistics (admin only).
  """
  def get_platform_stats(user_id) do
    if is_admin?(user_id) do
      stats = from(v in Video,
                   where: v.is_active == true,
                   select: %{
                     total_videos: count(v.id),
                     total_views: sum(v.views_count),
                     total_likes: sum(v.likes_count),
                     total_comments: sum(v.comments_count),
                     total_shares: sum(v.shares_count)
                   })
              |> Repo.one()

      {:ok, stats}
    else
      {:error, :access_denied}
    end
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

  defp is_moderator?(user_id) do
    case Weibaobe.Accounts.get_user(user_id) do
      {:ok, %{user_type: type}} when type in ["admin", "moderator"] -> true
      _ -> false
    end
  end

  @doc """
  Adds virtual fields to videos for user context.
  """
  def add_user_context_to_videos(videos, user_id) when is_list(videos) do
    video_ids = Enum.map(videos, & &1.id)

    # Get liked video IDs
    liked_video_ids = if user_id do
      VideoLike
      |> where([vl], vl.user_id == ^user_id and vl.video_id in ^video_ids)
      |> select([vl], vl.video_id)
      |> Repo.all()
      |> MapSet.new()
    else
      MapSet.new()
    end

    # Add virtual fields
    Enum.map(videos, fn video ->
      %{video | is_liked: MapSet.member?(liked_video_ids, video.id)}
    end)
  end

  def add_user_context_to_videos(videos, _user_id), do: videos

  @doc """
  Adds virtual fields to comments for user context.
  """
  def add_user_context_to_comments(comments, user_id) when is_list(comments) do
    comment_ids = Enum.map(comments, & &1.id)

    # Get liked comment IDs
    liked_comment_ids = if user_id do
      CommentLike
      |> where([cl], cl.user_id == ^user_id and cl.comment_id in ^comment_ids)
      |> select([cl], cl.comment_id)
      |> Repo.all()
      |> MapSet.new()
    else
      MapSet.new()
    end

    # Add virtual fields
    Enum.map(comments, fn comment ->
      can_delete = user_id && (comment.author_id == user_id || is_moderator?(user_id))

      %{comment |
        is_liked: MapSet.member?(liked_comment_ids, comment.id),
        can_delete: can_delete
      }
    end)
  end

  def add_user_context_to_comments(comments, _user_id), do: comments
end
