defmodule Weibaobe.Content.Video do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "videos" do
    field :user_id, :string
    field :user_name, :string
    field :user_image, :string, default: ""
    field :video_url, :string, default: ""
    field :thumbnail_url, :string, default: ""
    field :caption, :string, default: ""
    field :likes_count, :integer, default: 0
    field :comments_count, :integer, default: 0
    field :views_count, :integer, default: 0
    field :shares_count, :integer, default: 0
    field :tags, {:array, :string}, default: []
    field :is_active, :boolean, default: true
    field :is_featured, :boolean, default: false
    field :is_multiple_images, :boolean, default: false
    field :image_urls, {:array, :string}, default: []

    # Virtual fields (computed at runtime)
    field :is_liked, :boolean, virtual: true
    field :is_following, :boolean, virtual: true

    timestamps(type: :utc_datetime)

    # Associations
    belongs_to :user, Weibaobe.Accounts.User, foreign_key: :user_id, references: :uid, type: :string
    has_many :comments, Weibaobe.Content.Comment, foreign_key: :video_id, references: :id
    has_many :video_likes, Weibaobe.Content.VideoLike, foreign_key: :video_id, references: :id
  end

  @doc false
  def changeset(video, attrs) do
    video
    |> cast(attrs, [
      :user_id, :user_name, :user_image, :video_url, :thumbnail_url, :caption,
      :likes_count, :comments_count, :views_count, :shares_count, :tags,
      :is_active, :is_featured, :is_multiple_images, :image_urls
    ])
    |> validate_required([:user_id, :user_name, :caption])
    |> validate_length(:caption, min: 1, max: 2200)
    |> validate_number(:likes_count, greater_than_or_equal_to: 0)
    |> validate_number(:comments_count, greater_than_or_equal_to: 0)
    |> validate_number(:views_count, greater_than_or_equal_to: 0)
    |> validate_number(:shares_count, greater_than_or_equal_to: 0)
    |> validate_content()
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Creates a changeset for video creation
  """
  def create_changeset(video, attrs) do
    video
    |> cast(attrs, [
      :user_id, :user_name, :user_image, :video_url, :thumbnail_url,
      :caption, :tags, :is_multiple_images, :image_urls
    ])
    |> validate_required([:user_id, :user_name, :caption])
    |> validate_length(:caption, min: 1, max: 2200)
    |> validate_content()
    |> put_change(:likes_count, 0)
    |> put_change(:comments_count, 0)
    |> put_change(:views_count, 0)
    |> put_change(:shares_count, 0)
    |> put_change(:is_active, true)
    |> put_change(:is_featured, false)
  end

  @doc """
  Updates video content
  """
  def update_changeset(video, attrs) do
    video
    |> cast(attrs, [:caption, :tags, :thumbnail_url])
    |> validate_length(:caption, min: 1, max: 2200)
    |> put_change(:updated_at, DateTime.utc_now())
  end

  @doc """
  Admin changeset for moderation
  """
  def admin_changeset(video, attrs) do
    video
    |> cast(attrs, [:is_active, :is_featured])
    |> put_change(:updated_at, DateTime.utc_now())
  end

  # Validation functions

  defp validate_content(changeset) do
    is_multiple_images = get_field(changeset, :is_multiple_images)
    video_url = get_field(changeset, :video_url)
    image_urls = get_field(changeset, :image_urls) || []

    cond do
      is_multiple_images && Enum.empty?(image_urls) ->
        add_error(changeset, :image_urls, "are required for image posts")

      !is_multiple_images && (is_nil(video_url) || video_url == "") ->
        add_error(changeset, :video_url, "is required for video posts")

      true ->
        changeset
    end
  end

  # Helper functions

  def is_image_post?(%__MODULE__{is_multiple_images: true, image_urls: urls}) when length(urls) > 0, do: true
  def is_image_post?(_), do: false

  def is_video_post?(%__MODULE__{is_multiple_images: false, video_url: url}) when url != "" and not is_nil(url), do: true
  def is_video_post?(_), do: false

  def display_url(%__MODULE__{} = video) do
    cond do
      is_image_post?(video) -> List.first(video.image_urls)
      video.thumbnail_url != "" -> video.thumbnail_url
      true -> video.video_url
    end
  end

  def media_count(%__MODULE__{is_multiple_images: true, image_urls: urls}), do: length(urls)
  def media_count(_), do: 1

  def has_content?(%__MODULE__{} = video) do
    is_video_post?(video) || is_image_post?(video)
  end

  def valid_for_creation?(attrs) do
    %__MODULE__{}
    |> create_changeset(attrs)
    |> Map.get(:valid?)
  end

  def creation_errors(attrs) do
    %__MODULE__{}
    |> create_changeset(attrs)
    |> Map.get(:errors)
  end

  @doc """
  Calculates trending score based on engagement and recency
  """
  def trending_score(%__MODULE__{} = video) do
    hours_old = DateTime.diff(DateTime.utc_now(), video.inserted_at, :second) / 3600
    hours_old = if hours_old == 0, do: 1, else: hours_old

    # Weight recent videos higher
    time_decay = 1.0 / (1.0 + hours_old / 24.0)

    # Engagement score
    engagement_score = video.likes_count * 2 + video.comments_count * 3 +
                       video.shares_count * 5 + video.views_count

    engagement_score * time_decay
  end

  @doc """
  Calculates engagement rate
  """
  def engagement_rate(%__MODULE__{views_count: 0}), do: 0.0
  def engagement_rate(%__MODULE__{} = video) do
    total_engagement = video.likes_count + video.comments_count + video.shares_count
    (total_engagement / video.views_count) * 100
  end
end
