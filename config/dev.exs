import Config

# Configure your DigitalOcean PostgreSQL database
config :weibaobe, Weibaobe.Repo,
  username: System.get_env("DB_USER") || "postgres",
  password: System.get_env("DB_PASSWORD") || "postgres",
  hostname: System.get_env("DB_HOST") || "localhost",
  port: String.to_integer(System.get_env("DB_PORT") || "5432"),
  database: System.get_env("DB_NAME") || "weibaobe_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  # DigitalOcean requires SSL connection
  ssl: true,
  ssl_opts: [
    # DigitalOcean managed databases use SSL mode "require"
    verify: :verify_none,
    # Accept any certificate for managed database
    server_name_indication: :disable,
    # Use TLS v1.2 or higher
    versions: [:"tlsv1.2", :"tlsv1.3"]
  ],
  # Connection parameters for DigitalOcean
  parameters: [
    sslmode: "require"
  ],
  # Increase timeout for DigitalOcean connections
  timeout: 15_000,
  ownership_timeout: 15_000

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we can use it
# to bundle .js and .css sources.
config :weibaobe, WeibaobeWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "DskYCjbmO0mzzgrbwoqgKxdej36H2H0XQkIoxmGtqzp6Nq2Q69YISmtLV74aVk19",
  watchers: []

# Enable dev routes for dashboard and mailbox
config :weibaobe, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false
