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

  def
end
