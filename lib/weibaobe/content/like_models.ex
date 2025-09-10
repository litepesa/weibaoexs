defmodule Weibaobe.Content.VideoLike do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "video_likes" do
    field :video_id, Ecto.UUID
    field :user_id, :string

    timestamps(type: :utc_datetime, updated_at: false)

    # Associations
    belongs_to :video, Weibaobe.Content.Video, foreign_key: :video_id, references: :id, define_field: false
    belongs_to :user, Weibaobe.Accounts.User, foreign_key: :user_id, references: :uid, type: :string, define_field: false
  end

  def changeset(video_like, attrs) do
    video_like
    |> cast(attrs, [:video_id, :user_id])
    |> validate_required([:video_id, :user_id])
    |> unique_constraint([:video_id, :user_id])
    |> foreign_key_constraint(:video_id)
    |> foreign_key_constraint(:user_id)
  end
end

defmodule Weibaobe.Content.CommentLike do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "comment_likes" do
    field :comment_id, Ecto.UUID
    field :user_id, :string

    timestamps(type: :utc_datetime, updated_at: false)

    # Associations
    belongs_to :comment, Weibaobe.Content.Comment, foreign_key: :comment_id, references: :id, define_field: false
    belongs_to :user, Weibaobe.Accounts.User, foreign_key: :user_id, references: :uid, type: :string, define_field: false
  end

  def changeset(comment_like, attrs) do
    comment_like
    |> cast(attrs, [:comment_id, :user_id])
    |> validate_required([:comment_id, :user_id])
    |> unique_constraint([:comment_id, :user_id])
    |> foreign_key_constraint(:comment_id)
    |> foreign_key_constraint(:user_id)
  end
end

defmodule Weibaobe.Social.UserFollow do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "user_follows" do
    field :follower_id, :string
    field :following_id, :string

    timestamps(type: :utc_datetime, updated_at: false)

    # Associations
    belongs_to :follower, Weibaobe.Accounts.User, foreign_key: :follower_id, references: :uid, type: :string, define_field: false
    belongs_to :following, Weibaobe.Accounts.User, foreign_key: :following_id, references: :uid, type: :string, define_field: false
  end

  def changeset(user_follow, attrs) do
    user_follow
    |> cast(attrs, [:follower_id, :following_id])
    |> validate_required([:follower_id, :following_id])
    |> validate_not_self_follow()
    |> unique_constraint([:follower_id, :following_id])
    |> foreign_key_constraint(:follower_id)
    |> foreign_key_constraint(:following_id)
  end

  defp validate_not_self_follow(changeset) do
    follower_id = get_field(changeset, :follower_id)
    following_id = get_field(changeset, :following_id)

    if follower_id == following_id do
      add_error(changeset, :following_id, "cannot follow yourself")
    else
      changeset
    end
  end
end
