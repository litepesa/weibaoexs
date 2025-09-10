defmodule Weibaobe.Services.FirebaseAuth do
  @moduledoc """
  Firebase Authentication service for verifying ID tokens
  """

  require Logger

  @doc """
  Verifies a Firebase ID token and returns the token claims
  """
  def verify_id_token(id_token) do
    with {:ok, project_id} <- get_project_id(),
         {:ok, claims} <- decode_token(id_token, project_id) do
      {:ok, claims}
    else
      {:error, reason} ->
        Logger.warning("Firebase token verification failed: #{inspect(reason)}")
        {:error, :invalid_token}
    end
  end

  @doc """
  Gets Firebase user information by UID using Goth token
  """
  def get_user(uid) do
    with {:ok, token} <- get_admin_token(),
         {:ok, project_id} <- get_project_id() do

      # Use Tesla for HTTP request
      client = Tesla.client([
        Tesla.Middleware.BaseURL,
        Tesla.Middleware.JSON,
        {Tesla.Middleware.Headers, [{"authorization", "Bearer #{token}"}]}
      ])

      url = "https://identitytoolkit.googleapis.com/v1/accounts:lookup"

      body = %{
        "localId" => [uid]
      }

      case Tesla.post(client, url, body) do
        {:ok, %Tesla.Env{status: 200, body: %{"users" => [user]}}} ->
          {:ok, normalize_user(user)}

        {:ok, %Tesla.Env{status: 200, body: %{"users" => []}}} ->
          {:error, :user_not_found}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          Logger.error("Firebase get_user failed: #{status} - #{inspect(body)}")
          {:error, :firebase_error}

        {:error, reason} ->
          Logger.error("Firebase get_user request failed: #{inspect(reason)}")
          {:error, :request_failed}
      end
    else
      error -> error
    end
  end

  @doc """
  Decodes and verifies Firebase ID token using Joken
  """
  defp decode_token(id_token, project_id) do
    with {:ok, keys} <- get_firebase_keys(),
         {:ok, header} <- peek_header(id_token),
         {:ok, key} <- find_key(keys, header["kid"]),
         {:ok, claims} <- verify_with_joken(id_token, key, project_id) do
      {:ok, claims}
    end
  end

  defp get_firebase_keys do
    url = "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"

    case Tesla.get(url) do
      {:ok, %Tesla.Env{status: 200, body: keys}} when is_map(keys) ->
        {:ok, keys}

      {:ok, %Tesla.Env{status: status}} ->
        Logger.error("Failed to fetch Firebase keys: HTTP #{status}")
        {:error, :fetch_keys_failed}

      {:error, reason} ->
        Logger.error("Failed to fetch Firebase keys: #{inspect(reason)}")
        {:error, :fetch_keys_failed}
    end
  end

  defp find_key(keys, kid) when is_binary(kid) do
    case Map.get(keys, kid) do
      nil -> {:error, :key_not_found}
      key -> {:ok, key}
    end
  end
  defp find_key(_, _), do: {:error, :invalid_kid}

  defp verify_with_joken(token, public_key_pem, project_id) do
    try do
      signer = Joken.Signer.create("RS256", %{"pem" => public_key_pem})

      # Basic token verification
      case Joken.verify(token, signer) do
        {:ok, claims} ->
          # Additional Firebase-specific validations
          now = System.system_time(:second)

          cond do
            claims["exp"] <= now ->
              {:error, :token_expired}

            claims["iat"] > now ->
              {:error, :token_used_too_early}

            claims["iss"] != "https://securetoken.google.com/#{project_id}" ->
              {:error, :invalid_issuer}

            claims["aud"] != project_id ->
              {:error, :invalid_audience}

            not is_binary(claims["sub"]) or String.length(claims["sub"]) == 0 ->
              {:error, :invalid_subject}

            String.length(claims["sub"]) > 128 ->
              {:error, :subject_too_long}

            true ->
              {:ok, normalize_claims(claims)}
          end

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Token verification error: #{inspect(error)}")
        {:error, :verification_failed}
    end
  end

  defp normalize_claims(claims) do
    %{
      "uid" => claims["sub"],
      "email" => claims["email"],
      "phone_number" => claims["phone_number"],
      "name" => claims["name"],
      "picture" => claims["picture"],
      "email_verified" => claims["email_verified"] || false,
      "phone_verified" => claims["phone_number"] != nil,
      "auth_time" => claims["auth_time"],
      "exp" => claims["exp"],
      "iat" => claims["iat"],
      "iss" => claims["iss"],
      "aud" => claims["aud"],
      "firebase" => claims["firebase"] || %{}
    }
  end

  defp normalize_user(user) do
    %{
      "uid" => user["localId"],
      "email" => user["email"],
      "phone_number" => user["phoneNumber"],
      "display_name" => user["displayName"],
      "photo_url" => user["photoUrl"],
      "email_verified" => user["emailVerified"] || false,
      "disabled" => user["disabled"] || false,
      "created_at" => user["createdAt"],
      "last_login_at" => user["lastLoginAt"],
      "provider_user_info" => user["providerUserInfo"] || []
    }
  end

  defp get_project_id do
    case Application.get_env(:weibaobe, :firebase)[:project_id] do
      nil -> {:error, :missing_project_id}
      project_id when is_binary(project_id) -> {:ok, project_id}
      {:system, env_var} ->
        case System.get_env(env_var) do
          nil -> {:error, :missing_project_id}
          project_id -> {:ok, project_id}
        end
    end
  end

  defp get_admin_token do
    case Goth.Token.for_scope("https://www.googleapis.com/auth/identitytoolkit") do
      {:ok, %Goth.Token{token: token}} -> {:ok, token}
      {:error, reason} ->
        Logger.error("Failed to get admin token: #{inspect(reason)}")
        {:error, :admin_token_failed}
    end
  end

  @doc """
  Extracts header from JWT token without verification
  """
  defp peek_header(token) do
    case String.split(token, ".") do
      [header_b64, _payload_b64, _signature_b64] ->
        case Base.url_decode64(header_b64, padding: false) do
          {:ok, header_json} ->
            case Jason.decode(header_json) do
              {:ok, header} -> {:ok, header}
              {:error, _} -> {:error, :invalid_header}
            end

          :error -> {:error, :invalid_header}
        end

      _ -> {:error, :invalid_token_format}
    end
  end

  @doc """
  Health check for Firebase service
  """
  def health_check do
    with {:ok, _project_id} <- get_project_id(),
         {:ok, keys} <- get_firebase_keys() do
      if is_map(keys) do
        {:ok, :healthy}
      else
        {:error, :invalid_keys_format}
      end
    else
      error -> {:error, error}
    end
  end
end
