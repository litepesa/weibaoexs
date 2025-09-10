defmodule Weibaobe.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:uid, :string, []}
  @derive {Phoenix.Param, key: :uid}

  schema "users" do
    field :name, :string
    field :phone_number, :string
    field :profile_image, :string, default: ""
    field :cover_image, :string, default: ""
    field :bio, :string, default: ""
    field :user_type, :string, default: "user"
    field :followers_count, :integer, default: 0
    field :following_count, :integer, default: 0
    field :videos_count, :integer, default: 0
    field :likes_count, :integer, default: 0
    field :is_verified, :boolean, default: false
    field :is_active, :boolean, default: true
    field :is_featured, :boolean, default: false
    field :tags, {:array, :string}, default: []
    field :last_seen, :utc_datetime

    # Virtual fields (computed at runtime)
    field :is_following, :boolean, virtual: true
    field :is_current_user, :boolean, virtual: true

    timestamps(type: :utc_datetime)

    # Associations
    has_many :videos, Weibaobe.Content.Video, foreign_key: :user_id, references: :uid
    has_many :comments, Weibaobe.Content.Comment, foreign_key: :author_id, references: :uid
    has_many :video_likes, Weibaobe.Content.VideoLike, foreign_key: :user_id, references: :uid
    has_many :comment_likes, Weibaobe.Content.CommentLike, foreign_key: :user_id, references: :uid
    has_many :followers, Weibaobe.Social.UserFollow, foreign_key: :following_id, references: :uid
    has_many :following, Weibaobe.Social.UserFollow, foreign_key: :follower_id, references: :uid
    has_one :wallet, Weibaobe.Finance.Wallet, foreign_key: :user_id, references: :uid
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :uid, :name, :phone_number, :profile_image, :cover_image, :bio,
      :user_type, :followers_count, :following_count, :videos_count, :likes_count,
      :is_verified, :is_active, :is_featured, :tags, :last_seen
    ])
    |> validate_required([:uid, :name, :phone_number])
    |> validate_length(:name, min: 2, max: 50)
    |> validate_length(:bio, max: 160)
    |> validate_inclusion(:user_type, ["user", "admin", "moderator"])
    |> validate_number(:followers_count, greater_than_or_equal_to: 0)
    |> validate_number(:following_count, greater_than_or_equal_to: 0)
    |> validate_number(:videos_count, greater_than_or_equal_to: 0)
    |> validate_number(:likes_count, greater_than_or_equal_to: 0)
    |> unique_constraint(:uid, name: :users_pkey)
    |> unique_constraint(:phone_number)
  end

  @doc """
  Creates a changeset for user creation/sync from Firebase
  """
  def sync_changeset(user, attrs) do
    user
    |> cast(attrs, [:uid, :name, :phone_number, :profile_image, :bio])
    |> validate_required([:uid, :phone_number])
    |> validate_length(:name, min: 1, max: 50)
    |> validate_length(:bio, max: 160)
    |> put_change(:last_seen, DateTime.utc_now())
    |> put_change(:is_active, true)
    |> unique_constraint(:uid, name: :users_pkey)
    |> unique_constraint(:phone_number)
  end

  @doc """
  Updates user profile information
  """
  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :profile_image, :cover_image, :bio, :tags])
    |> validate_length(:name, min: 2, max: 50)
    |> validate_length(:bio, max: 160)
    |> validate_length(:tags, max: 10)
    |> put_change(:updated_at, DateTime.utc_now())
    |> put_change(:last_seen, DateTime.utc_now())
  end

  @doc """
  Admin changeset for updating user status
  """
  def admin_changeset(user, attrs) do
    user
    |> cast(attrs, [:user_type, :is_verified, :is_active, :is_featured])
    |> validate_inclusion(:user_type, ["user", "admin", "moderator"])
    |> put_change(:updated_at, DateTime.utc_now())
  end

  @doc """
  Updates last seen timestamp
  """
  def update_last_seen(user) do
    user
    |> change(last_seen: DateTime.utc_now(), updated_at: DateTime.utc_now())
  end

  # Helper functions

  def is_admin?(%__MODULE__{user_type: "admin"}), do: true
  def is_admin?(_), do: false

  def is_moderator?(%__MODULE__{user_type: type}) when type in ["moderator", "admin"], do: true
  def is_moderator?(_), do: false

  def can_moderate?(user), do: is_moderator?(user)
  def can_manage_users?(user), do: is_admin?(user)

  def has_minimum_followers?(user, min), do: user.followers_count >= min

  def engagement_rate(user) do
    if user.followers_count > 0 do
      (user.videos_count / user.followers_count) * 100
    else
      0.0
    end
  end

  def display_name(user) do
    if user.name != "" and not is_nil(user.name) do
      user.name
    else
      user.phone_number
    end
  end

  def profile_image_or_default(user) do
    if user.profile_image != "" and not is_nil(user.profile_image) do
      user.profile_image
    else
      "/assets/default-avatar.png"
    end
  end

  @doc """
  Validates user data for creation
  """
  def valid_for_creation?(attrs) do
    %__MODULE__{}
    |> sync_changeset(attrs)
    |> Map.get(:valid?)
  end

  @doc """
  Returns validation errors for creation
  """
  def creation_errors(attrs) do
    %__MODULE__{}
    |> sync_changeset(attrs)
    |> Map.get(:errors)
  end
end
