import Config

config :tokenio,
  sandbox_base_url: "https://api.sandbox.token.io",
  production_base_url: "https://api.token.io",
  pool_size: 10,
  pool_count: 1

import_config "#{config_env()}.exs"
