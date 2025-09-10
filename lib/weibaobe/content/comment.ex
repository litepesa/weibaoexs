defmodule Weibaobe.Content.Comment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "comments" do
    field :video_id, Ecto.UUID
    field :author_id, :string
    field :author_name, :string
    field :author_image, :string, default: ""
    field :content, :string
    field :likes_count, :integer, default: 0
    field :is_reply, :boolean, default: false
    field :replied_to_comment_id, Ecto.UUID
    field :replied_to_author_name, :string

    # Virtual fields
    field :is_liked, :boolean, virtual: true
    field :can_delete, :boolean, virtual: true

    timestamps(type: :utc_datetime)

    # Associations
    belongs_to :video, Weibaobe.Content.Video, foreign_key: :video_id, references: :id, define_field: false
    belongs_to :author, Weibaobe.Accounts.User, foreign_key: :author_id, references: :uid, type: :string, define_field: false
    belongs_to :replied_to_comment, __MODULE__, foreign_key: :replied_to_comment_id, references: :id, define_field: false
    has_many :replies, __MODULE__, foreign_key: :replied_to_comment_id, references: :id
    has_many :comment_likes, Weibaobe.Content.CommentLike, foreign_key: :comment_id, references: :id
  end

  @doc false
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [
      :video_id, :author_id, :author_name, :author_image, :content,
      :likes_count, :is_reply, :replied_to_comment_id, :replied_to_author_name
    ])
    |> validate_required([:video_id, :author_id, :author_name, :content])
    |> validate_length(:content, min: 1, max: 500)
    |> validate_reply()
    |> foreign_key_constraint(:video_id)
    |> foreign_key_constraint(:author_id)
    |> foreign_key_constraint(:replied_to_comment_id)
  end

  @doc """
  Creates a changeset for comment creation
  """
  def create_changeset(comment, attrs) do
    comment
    |> cast(attrs, [
      :video_id, :author_id, :author_name, :author_image, :content,
      :replied_to_comment_id, :replied_to_author_name
    ])
    |> validate_required([:video_id, :author_id, :author_name, :content])
    |> validate_length(:content, min: 1, max: 500)
    |> validate_reply()
    |> set_reply_status()
    |> put_change(:likes_count, 0)
  end

  defp validate_reply(changeset) do
    replied_to_comment_id = get_field(changeset, :replied_to_comment_id)

    if replied_to_comment_id && get_field(changeset, :replied_to_author_name) in [nil, ""] do
      add_error(changeset, :replied_to_author_name, "is required for replies")
    else
      changeset
    end
  end

  defp set_reply_status(changeset) do
    replied_to_comment_id = get_field(changeset, :replied_to_comment_id)
    put_change(changeset, :is_reply, not is_nil(replied_to_comment_id))
  end

  def is_valid_reply?(%__MODULE__{is_reply: true, replied_to_comment_id: id}) when not is_nil(id), do: true
  def is_valid_reply?(_), do: false

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
end
