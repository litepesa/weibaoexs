defmodule WeibaobeWeb.CommentController do
  use WeibaobeWeb, :controller

  alias Weibaobe.Content
  alias Weibaobe.Accounts

  action_fallback WeibaobeWeb.FallbackController

  @doc """
  Get comments for a video (PUBLIC)
  """
  def index(conn, %{"videoId" => video_id} = params) do
    limit = parse_int(params["limit"], 20, 100)
    offset = parse_int(params["offset"], 0, nil)

    comments = Content.get_video_comments(video_id, limit, offset)
    current_user_id = conn.assigns[:current_user_id]

    formatted_comments = comments
                        |> Content.add_user_context_to_comments(current_user_id)
                        |> Enum.map(&format_comment_response/1)

    conn
    |> json(%{
      comments: formatted_comments,
      total: length(comments)
    })
  end

  @doc """
  Create a comment (REQUIRES AUTH)
  """
  def create(conn, %{"videoId" => video_id} = params) do
    user_id = conn.assigns.current_user_id

    # Get user info for comment
    case Accounts.get_user(user_id) do
      {:ok, user} ->
        comment_attrs = %{
          "video_id" => video_id,
          "author_id" => user_id,
          "author_name" => user.name,
          "author_image" => user.profile_image,
          "content" => params["content"],
          "replied_to_comment_id" => params["repliedToCommentId"],
          "replied_to_author_name" => params["repliedToAuthorName"]
        }

        case Content.create_comment(comment_attrs) do
          {:ok, comment} ->
            conn
            |> put_status(:created)
            |> json(%{
              commentId: comment.id,
              message: "Comment created successfully"
            })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: "Failed to create comment",
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
  Delete a comment (REQUIRES AUTH - author or moderator)
  """
  def delete(conn, %{"commentId" => comment_id}) do
    user_id = conn.assigns.current_user_id

    case Content.delete_comment(comment_id, user_id) do
      {:ok, :deleted} ->
        conn |> json(%{message: "Comment deleted successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Comment not found"})

      {:error, :access_denied} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied"})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to delete comment"})
    end
  end

  @doc """
  Like a comment (REQUIRES AUTH)
  """
  def like(conn, %{"commentId" => comment_id}) do
    user_id = conn.assigns.current_user_id

    case Content.like_comment(comment_id, user_id) do
      {:ok, :liked} ->
        conn |> json(%{message: "Comment liked successfully"})

      {:error, :already_liked} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Comment already liked"})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to like comment"})
    end
  end

  @doc """
  Unlike a comment (REQUIRES AUTH)
  """
  def unlike(conn, %{"commentId" => comment_id}) do
    user_id = conn.assigns.current_user_id

    case Content.unlike_comment(comment_id, user_id) do
      {:ok, :unliked} ->
        conn |> json(%{message: "Comment unliked successfully"})

      {:error, :not_liked} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Comment not liked"})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to unlike comment"})
    end
  end

  # Private helper functions

  defp format_comment_response(comment) do
    %{
      id: comment.id,
      videoId: comment.video_id,
      authorId: comment.author_id,
      authorName: comment.author_name,
      authorImage: comment.author_image,
      content: comment.content,
      likesCount: comment.likes_count,
      isReply: comment.is_reply,
      repliedToCommentId: comment.replied_to_comment_id,
      repliedToAuthorName: comment.replied_to_author_name,
      createdAt: comment.inserted_at,
      updatedAt: comment.updated_at,
      # Virtual fields
      isLiked: Map.get(comment, :is_liked, false),
      canDelete: Map.get(comment, :can_delete, false)
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
end
