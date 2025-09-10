defmodule WeibaobeWeb.VideoController do
  use WeibaobeWeb, :controller

  alias Weibaobe.Content
  alias Weibaobe.Social
  alias Weibaobe.Accounts

  action_fallback WeibaobeWeb.FallbackController

  # ===============================
  # PUBLIC VIDEO ENDPOINTS
  # ===============================

  @doc """
  List videos with filtering and pagination (PUBLIC)
  """
  def index(conn, params) do
    opts = [
      limit: parse_int(params["limit"], 20, 100),
      offset: parse_int(params["offset"], 0, nil),
      user_id: params["userId"],
      featured: parse_boolean(params["featured"]),
      media_type: params["mediaType"],
      sort_by: params["sortBy"] || "latest",
      query: params["q"]
    ]

    videos = Content.list_videos(opts)
    current_user_id = conn.assigns[:current_user_id]

    formatted_videos = videos
                      |> Content.add_user_context_to_videos(current_user_id)
                      |> Enum.map(&format_video_response/1)

    conn
    |> json(%{
      videos: formatted_videos,
      total: length(videos)
    })
  end

  @doc """
  Get featured videos (PUBLIC)
  """
  def featured(conn, params) do
    limit = parse_int(params["limit"], 10, 50)

    videos = Content.get_featured_videos(limit)
    current_user_id = conn.assigns[:current_user_id]

    formatted_videos = videos
                      |> Content.add_user_context_to_videos(current_user_id)
                      |> Enum.map(&format_video_response/1)

    conn
    |> json(%{
      videos: formatted_videos,
      total: length(videos)
    })
  end

  @doc """
  Get trending videos (PUBLIC)
  """
  def trending(conn, params) do
    limit = parse_int(params["limit"], 10, 50)

    videos = Content.get_trending_videos(limit)
    current_user_id = conn.assigns[:current_user_id]

    formatted_videos = videos
                      |> Content.add_user_context_to_videos(current_user_id)
                      |> Enum.map(&format_video_response/1)

    conn
    |> json(%{
      videos: formatted_videos,
      total: length(videos)
    })
  end

  @doc """
  Get single video by ID (PUBLIC)
  """
  def show(conn, %{"videoId" => video_id}) do
    case Content.get_video_and_increment_views(video_id) do
      {:ok, video} ->
        current_user_id = conn.assigns[:current_user_id]

        formatted_video = [video]
                         |> Content.add_user_context_to_videos(current_user_id)
                         |> List.first()
                         |> format_video_response()

        conn |> json(formatted_video)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found"})
    end
  end

  @doc """
  Get videos by user (PUBLIC)
  """
  def user_videos(conn, %{"userId" => user_id} = params) do
    limit = parse_int(params["limit"], 20, 100)
    offset = parse_int(params["offset"], 0, nil)

    videos = Content.get_user_videos(user_id, limit, offset)
    current_user_id = conn.assigns[:current_user_id]

    formatted_videos = videos
                      |> Content.add_user_context_to_videos(current_user_id)
                      |> Enum.map(&format_video_response/1)

    conn
    |> json(%{
      videos: formatted_videos,
      total: length(videos),
      userId: user_id
    })
  end

  @doc """
  Increment video views (PUBLIC)
  """
  def increment_views(conn, %{"videoId" => video_id}) do
    Content.increment_video_views(video_id)

    conn |> json(%{message: "View counted successfully"})
  end

  # ===============================
  # VIDEO INTERACTION ENDPOINTS
  # ===============================

  @doc """
  Like a video (REQUIRES AUTH)
  """
  def like_video(conn, %{"videoId" => video_id}) do
    user_id = conn.assigns.current_user_id

    case Content.like_video(video_id, user_id) do
      {:ok, :liked} ->
        conn |> json(%{message: "Video liked successfully"})

      {:error, :already_liked} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Video already liked"})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to like video"})
    end
  end

  @doc """
  Unlike a video (REQUIRES AUTH)
  """
  def unlike_video(conn, %{"videoId" => video_id}) do
    user_id = conn.assigns.current_user_id

    case Content.unlike_video(video_id, user_id) do
      {:ok, :unliked} ->
        conn |> json(%{message: "Video unliked successfully"})

      {:error, :not_liked} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Video not liked"})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to unlike video"})
    end
  end

  @doc """
  Share a video (PUBLIC)
  """
  def share_video(conn, %{"videoId" => video_id}) do
    Content.increment_video_shares(video_id)

    conn |> json(%{message: "Video shared successfully"})
  end

  @doc """
  Get user's liked videos (REQUIRES AUTH - own videos only)
  """
  def user_liked_videos(conn, %{"userId" => user_id} = params) do
    requesting_user_id = conn.assigns.current_user_id

    # Users can only view their own liked videos unless admin
    if requesting_user_id == user_id or is_admin?(conn.assigns.current_user) do
      limit = parse_int(params["limit"], 20, 100)
      offset = parse_int(params["offset"], 0, nil)

      videos = Content.get_user_liked_videos(user_id, limit, offset)

      formatted_videos = videos
                        |> Content.add_user_context_to_videos(requesting_user_id)
                        |> Enum.map(&format_video_response/1)

      conn
      |> json(%{
        videos: formatted_videos,
        total: length(videos)
      })
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Access denied"})
    end
  end

  # ===============================
  # AUTHENTICATED VIDEO ENDPOINTS
  # ===============================

  @doc """
  Create a new video (REQUIRES AUTH)
  """
  def create(conn, params) do
    user_id = conn.assigns.current_user_id

    # Get user info for video
    case Accounts.get_user(user_id) do
      {:ok, user} ->
        video_attrs = %{
          "user_id" => user_id,
          "user_name" => user.name,
          "user_image" => user.profile_image,
          "caption" => params["caption"],
          "video_url" => params["videoUrl"] || "",
          "thumbnail_url" => params["thumbnailUrl"] || "",
          "tags" => params["tags"] || [],
          "is_multiple_images" => params["isMultipleImages"] || false,
          "image_urls" => params["imageUrls"] || []
        }

        case Content.create_video(video_attrs) do
          {:ok, video} ->
            conn
            |> put_status(:created)
            |> json(%{
              videoId: video.id,
              message: "Video created successfully"
            })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: "Failed to create video",
              details: format_changeset_errors(changeset)
            })
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})
    end
  end

  @doc """
  Update a video (REQUIRES AUTH - owner or admin)
  """
  def update(conn, %{"videoId" => video_id} = params) do
    user_id = conn.assigns.current_user_id

    case Content.get_video(video_id) do
      {:ok, video} ->
        update_attrs = %{}
        |> put_if_present("caption", params["caption"])
        |> put_if_present("tags", params["tags"])
        |> put_if_present("thumbnail_url", params["thumbnailUrl"])

        case Content.update_video(video, update_attrs, user_id) do
          {:ok, _updated_video} ->
            conn |> json(%{message: "Video updated successfully"})

          {:error, :access_denied} ->
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Access denied"})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: "Failed to update video",
              details: format_changeset_errors(changeset)
            })
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found"})
    end
  end

  @doc """
  Delete a video (REQUIRES AUTH - owner or admin)
  """
  def delete(conn, %{"videoId" => video_id}) do
    user_id = conn.assigns.current_user_id

    case Content.delete_video(video_id, user_id) do
      {:ok, :deleted} ->
        conn |> json(%{message: "Video deleted successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found"})

      {:error, :access_denied} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied"})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to delete video"})
    end
  end

  @doc """
  Get following feed (REQUIRES AUTH)
  """
  def following_feed(conn, params) do
    user_id = conn.assigns.current_user_id
    limit = parse_int(params["limit"], 20, 100)
    offset = parse_int(params["offset"], 0, nil)

    videos = Content.get_following_feed(user_id, limit, offset)

    formatted_videos = videos
                      |> Content.add_user_context_to_videos(user_id)
                      |> Enum.map(&format_video_response/1)

    conn
    |> json(%{
      videos: formatted_videos,
      total: length(videos)
    })
  end

  @doc """
  Get user video statistics (REQUIRES AUTH)
  """
  def video_stats(conn, _params) do
    user_id = conn.assigns.current_user_id

    stats = Content.get_user_video_stats(user_id)

    conn
    |> json(%{
      stats: stats,
      total: length(stats)
    })
  end

  # ===============================
  # ADMIN ENDPOINTS
  # ===============================

  @doc """
  Toggle video featured status (ADMIN ONLY)
  """
  def toggle_featured(conn, %{"videoId" => video_id} = params) do
    user_id = conn.assigns.current_user_id
    is_featured = params["isFeatured"] || false

    case Content.toggle_video_featured(video_id, is_featured, user_id) do
      {:ok, :updated} ->
        status = if is_featured, do: "featured", else: "unfeatured"
        conn |> json(%{message: "Video #{status} successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found"})

      {:error, :access_denied} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Admin access required"})
    end
  end

  @doc """
  Toggle video active status (ADMIN ONLY)
  """
  def toggle_active(conn, %{"videoId" => video_id} = params) do
    user_id = conn.assigns.current_user_id
    is_active = params["isActive"] || false

    case Content.toggle_video_active(video_id, is_active, user_id) do
      {:ok, :updated} ->
        status = if is_active, do: "activated", else: "deactivated"
        conn |> json(%{message: "Video #{status} successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Video not found"})

      {:error, :access_denied} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Admin access required"})
    end
  end

  # Private helper functions

  defp format_video_response(video) do
    %{
      id: video.id,
      userId: video.user_id,
      userName: video.user_name,
      userImage: video.user_image,
      videoUrl: video.video_url,
      thumbnailUrl: video.thumbnail_url,
      caption: video.caption,
      likesCount: video.likes_count,
      commentsCount: video.comments_count,
      viewsCount: video.views_count,
      sharesCount: video.shares_count,
      tags: video.tags,
      isActive: video.is_active,
      isFeatured: video.is_featured,
      isMultipleImages: video.is_multiple_images,
      imageUrls: video.image_urls,
      createdAt: video.inserted_at,
      updatedAt: video.updated_at,
      # Virtual fields
      isLiked: Map.get(video, :is_liked, false),
      isFollowing: Map.get(video, :is_following, false)
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
