defmodule Weibaobe.Services.R2Storage do
  @moduledoc """
  Cloudflare R2 storage service using ExAws S3-compatible API
  """

  require Logger

  @doc """
  Uploads a file to R2 storage
  """
  def upload_file(file_path, file_name, file_type, content_type \\ nil) do
    with {:ok, bucket_name} <- get_bucket_name(),
         {:ok, file_content} <- read_file(file_path),
         content_type <- content_type || guess_content_type(file_name),
         unique_key <- generate_unique_key(file_name, file_type) do

      upload_params = [
        {:acl, :public_read},
        {:content_type, content_type},
        {:cache_control, "public, max-age=31536000"} # 1 year cache
      ]

      case ExAws.S3.put_object(bucket_name, unique_key, file_content, upload_params)
           |> ExAws.request() do
        {:ok, _result} ->
          public_url = get_public_url(unique_key)
          Logger.info("File uploaded successfully: #{unique_key}")
          {:ok, public_url}

        {:error, {:http_error, status_code, %{body: body}}} ->
          Logger.error("R2 upload failed: HTTP #{status_code} - #{body}")
          {:error, :upload_failed}

        {:error, reason} ->
          Logger.error("R2 upload failed: #{inspect(reason)}")
          {:error, :upload_failed}
      end
    end
  end

  @doc """
  Uploads file from binary data
  """
  def upload_binary(binary_data, file_name, file_type, content_type \\ nil) do
    with {:ok, bucket_name} <- get_bucket_name(),
         content_type <- content_type || guess_content_type(file_name),
         unique_key <- generate_unique_key(file_name, file_type) do

      upload_params = [
        {:acl, :public_read},
        {:content_type, content_type},
        {:cache_control, "public, max-age=31536000"}
      ]

      case ExAws.S3.put_object(bucket_name, unique_key, binary_data, upload_params)
           |> ExAws.request() do
        {:ok, _result} ->
          public_url = get_public_url(unique_key)
          Logger.info("Binary data uploaded successfully: #{unique_key}")
          {:ok, public_url}

        {:error, {:http_error, status_code, %{body: body}}} ->
          Logger.error("R2 binary upload failed: HTTP #{status_code} - #{body}")
          {:error, :upload_failed}

        {:error, reason} ->
          Logger.error("R2 binary upload failed: #{inspect(reason)}")
          {:error, :upload_failed}
      end
    end
  end

  @doc """
  Uploads file from Plug.Upload struct
  """
  def upload_plug_file(%Plug.Upload{} = upload, file_type) do
    content_type = upload.content_type || guess_content_type(upload.filename)

    case File.read(upload.path) do
      {:ok, binary_data} ->
        upload_binary(binary_data, upload.filename, file_type, content_type)

      {:error, reason} ->
        Logger.error("Failed to read uploaded file: #{inspect(reason)}")
        {:error, :file_read_failed}
    end
  end

  @doc """
  Deletes a file from R2 storage
  """
  def delete_file(file_key) do
    with {:ok, bucket_name} <- get_bucket_name() do
      case ExAws.S3.delete_object(bucket_name, file_key) |> ExAws.request() do
        {:ok, _result} ->
          Logger.info("File deleted successfully: #{file_key}")
          {:ok, :deleted}

        {:error, {:http_error, 404, _}} ->
          Logger.warning("File not found for deletion: #{file_key}")
          {:ok, :not_found}

        {:error, reason} ->
          Logger.error("R2 delete failed: #{inspect(reason)}")
          {:error, :delete_failed}
      end
    end
  end

  @doc """
  Checks if a file exists in R2 storage
  """
  def file_exists?(file_key) do
    with {:ok, bucket_name} <- get_bucket_name() do
      case ExAws.S3.head_object(bucket_name, file_key) |> ExAws.request() do
        {:ok, _result} -> {:ok, true}
        {:error, {:http_error, 404, _}} -> {:ok, false}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Lists files in a specific prefix/folder
  """
  def list_files(prefix \\ "") do
    with {:ok, bucket_name} <- get_bucket_name() do
      case ExAws.S3.list_objects_v2(bucket_name, prefix: prefix) |> ExAws.request() do
        {:ok, %{body: %{contents: contents}}} ->
          files = Enum.map(contents, fn obj ->
            %{
              key: obj.key,
              size: obj.size,
              last_modified: obj.last_modified,
              url: get_public_url(obj.key)
            }
          end)
          {:ok, files}

        {:error, reason} ->
          Logger.error("R2 list files failed: #{inspect(reason)}")
          {:error, :list_failed}
      end
    end
  end

  @doc """
  Gets the public URL for a file
  """
  def get_public_url(file_key) do
    case get_public_base_url() do
      {:ok, base_url} -> "#{base_url}/#{file_key}"
      {:error, _} -> nil
    end
  end

  @doc """
  Generates a presigned URL for temporary access
  """
  def generate_presigned_url(file_key, expires_in \\ 3600) do
    with {:ok, bucket_name} <- get_bucket_name() do
      case ExAws.S3.presigned_url(:get, bucket_name, file_key, expires_in: expires_in) do
        {:ok, url} -> {:ok, url}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Health check for R2 service
  """
  def health_check do
    with {:ok, bucket_name} <- get_bucket_name() do
      case ExAws.S3.head_bucket(bucket_name) |> ExAws.request() do
        {:ok, _result} -> {:ok, :healthy}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # Private helper functions

  defp get_bucket_name do
    case Application.get_env(:weibaobe, :r2)[:bucket_name] do
      nil -> {:error, :missing_bucket_name}
      {:system, env_var} ->
        case System.get_env(env_var) do
          nil -> {:error, :missing_bucket_name}
          bucket -> {:ok, bucket}
        end
      bucket when is_binary(bucket) -> {:ok, bucket}
    end
  end

  defp get_public_base_url do
    case Application.get_env(:weibaobe, :r2)[:public_url] do
      nil -> {:error, :missing_public_url}
      {:system, env_var} ->
        case System.get_env(env_var) do
          nil -> {:error, :missing_public_url}
          url -> {:ok, String.trim_trailing(url, "/")}
        end
      url when is_binary(url) -> {:ok, String.trim_trailing(url, "/")}
    end
  end

  defp generate_unique_key(filename, file_type) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    uuid = UUID.uuid4() |> String.slice(0, 8)
    extension = Path.extname(filename)

    "#{file_type}/#{timestamp}_#{uuid}#{extension}"
  end

  defp read_file(file_path) do
    case File.read(file_path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end

  defp guess_content_type(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".webp" -> "image/webp"
      ".gif" -> "image/gif"
      ".mp4" -> "video/mp4"
      ".mov" -> "video/quicktime"
      ".avi" -> "video/avi"
      ".webm" -> "video/webm"
      ".ts" -> "video/mp2t"
      ".m3u8" -> "application/vnd.apple.mpegurl"
      ".mkv" -> "video/x-matroska"
      ".flv" -> "video/x-flv"
      ".wmv" -> "video/x-ms-wmv"
      _ -> "application/octet-stream"
    end
  end

  @doc """
  Validates file type and size for upload
  """
  def validate_upload(filename, file_size, file_type) do
    with {:ok, _} <- validate_file_extension(filename, file_type),
         {:ok, _} <- validate_file_size(file_size, file_type) do
      {:ok, :valid}
    end
  end

  defp validate_file_extension(filename, file_type) do
    extension = Path.extname(filename) |> String.downcase()

    allowed_extensions = case file_type do
      "banner" -> [".jpg", ".jpeg", ".png", ".webp", ".gif"]
      "thumbnail" -> [".jpg", ".jpeg", ".png", ".webp"]
      "profile" -> [".jpg", ".jpeg", ".png", ".webp"]
      "video" -> [".mp4", ".mov", ".avi", ".webm", ".ts", ".m3u8", ".mkv"]
      _ -> []
    end

    if extension in allowed_extensions do
      {:ok, :valid}
    else
      {:error, {:invalid_extension, extension, allowed_extensions}}
    end
  end

  defp validate_file_size(file_size, file_type) do
    max_sizes = %{
      "banner" => 10 * 1024 * 1024,      # 10MB
      "thumbnail" => 5 * 1024 * 1024,    # 5MB
      "profile" => 5 * 1024 * 1024,      # 5MB
      "video" => 1024 * 1024 * 1024      # 1GB
    }

    max_size = Map.get(max_sizes, file_type, 0)

    if file_size <= max_size do
      {:ok, :valid}
    else
      {:error, {:file_too_large, file_size, max_size}}
    end
  end

  @doc """
  Batch upload multiple files
  """
  def batch_upload(files, file_type) when is_list(files) do
    if length(files) > 20 do
      {:error, :too_many_files}
    else
      results = Enum.map(files, fn file ->
        case upload_plug_file(file, file_type) do
          {:ok, url} ->
            %{
              filename: file.filename,
              status: :success,
              url: url
            }

          {:error, reason} ->
            %{
              filename: file.filename,
              status: :error,
              error: reason
            }
        end
      end)

      success_count = Enum.count(results, fn result -> result.status == :success end)

      {:ok, %{
        total: length(files),
        successful: success_count,
        failed: length(files) - success_count,
        results: results
      }}
    end
  end

  def batch_upload(_, _), do: {:error, :invalid_input}
end
