import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# Load environment variables from .env file in development
if config_env() in [:dev, :test] do
  try do
    DotenvParser.load_file(".env")
  rescue
    _ -> :ok
  end
end

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/weibaobe start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :weibaobe, WeibaobeWeb.Endpoint, server: true
end

# Firebase Configuration
config :goth,
  json: System.get_env("FIREBASE_CREDENTIALS_JSON") ||
        (case System.get_env("FIREBASE_CREDENTIALS") do
          nil -> nil
          path -> File.read!(path)
        end)

config :weibaobe, :firebase,
  project_id: System.get_env("FIREBASE_PROJECT_ID")

# Cloudflare R2 Configuration
r2_account_id = System.get_env("R2_ACCOUNT_ID")

config :ex_aws,
  access_key_id: System.get_env("R2_ACCESS_KEY"),
  secret_access_key: System.get_env("R2_SECRET_KEY"),
  region: "auto"

if r2_account_id do
  config :ex_aws, :s3,
    scheme: "https://",
    host: "#{r2_account_id}.r2.cloudflarestorage.com",
    region: "auto"
end

config :weibaobe, :r2,
  account_id: r2_account_id,
  bucket_name: System.get_env("R2_BUCKET_NAME") || "weibaomedia",
  public_url: System.get_env("R2_PUBLIC_URL") || "https://pub-5e8ab62547db4f58851382161d280c19.r2.dev"

# CORS Configuration
allowed_origins =
  System.get_env("ALLOWED_ORIGINS", "http://localhost:3000,https://yourdomain.com")
  |> String.split(",")
  |> Enum.map(&String.trim/1)

config :cors_plug,
  origin: allowed_origins,
  max_age: 86400,
  methods: ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
  headers: ["Origin", "Content-Type", "Authorization", "Accept", "X-Requested-With"]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :weibaobe, Weibaobe.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :weibaobe, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :weibaobe, WeibaobeWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base
end
