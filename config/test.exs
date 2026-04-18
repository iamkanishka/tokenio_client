import Config

# Reduce pool size and timeouts in test environment
config :tokenio_client,
  pool_size: 2,
  pool_count: 1
