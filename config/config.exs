# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :weibaobe,
  ecto_repos: [Weibaobe.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :weibaobe, WeibaobeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: WeibaobeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Weibaobe.PubSub,
  live_view: [signing_salt: "QKy9UjZW"]

# Configures the mailer
config :weibaobe, Weibaobe.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version your project was generated with)
config :esbuild, :version, "0.25.0"

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Firebase Configuration
config :goth,
  json: {:system, "FIREBASE_CREDENTIALS_JSON"}

config :weibaobe, :firebase,
  project_id: {:system, "FIREBASE_PROJECT_ID"}

# Cloudflare R2 Configuration (S3-compatible)
config :ex_aws,
  access_key_id: {:system, "R2_ACCESS_KEY"},
  secret_access_key: {:system, "R2_SECRET_KEY"},
  region: "auto",
  json_codec: Jason

config :ex_aws, :s3,
  scheme: "https://",
  region: "auto"

config :weibaobe, :r2,
  account_id: {:system, "R2_ACCOUNT_ID"},
  bucket_name: {:system, "R2_BUCKET_NAME"},
  public_url: {:system, "R2_PUBLIC_URL"}

# CORS Configuration
config :cors_plug,
  origin: [
    "http://localhost:3000",
    "https://yourdomain.com"
  ],
  max_age: 86400,
  methods: ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]

# JWT Configuration for Firebase tokens
config :joken,
  default_signer: "HS256"

# Tesla HTTP client configuration
config :tesla, adapter: Tesla.Adapter.Hackney

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
