import Config

# Configure your database using individual environment variables
config :weibaobe, Weibaobe.Repo,
  username: System.get_env("DB_USERNAME"),
  password: System.get_env("DB_PASSWORD"),
  hostname: System.get_env("DB_HOST"),
  database: System.get_env("DB_NAME"),
  port: String.to_integer(System.get_env("DB_PORT") || "25060"),
  ssl: true,
  socket_options: [:inet6],
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# For development, we disable any cache and enable
# debugging and code reloading.
config :weibaobe, WeibaobeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "SECRET_KEY_BASE",
  watchers: []

# Enable dev routes for dashboard and mailbox
config :weibaobe, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Set a higher stacktrace during development
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false
