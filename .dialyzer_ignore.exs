# Dialyzer ignore file.
#
# contract_supertype warnings on private helper functions are suppressed here.
# These functions have specs that are intentionally broader than the inferred
# success type — the specs are correct but dialyzer flags the mismatch.
# This is a known dialyzer limitation with polymorphic helpers like put_if/3.
[
  # put_if/3 helpers — used with various map shapes; spec is intentionally broad
  ~r/lib\/tokenio_client\/apis\.ex.*contract_supertype/,
  ~r/lib\/tokenio_client\/payments\.ex.*contract_supertype/,
  ~r/lib\/tokenio_client\/vrp\.ex.*contract_supertype/,

  # HTTP client internal functions — tighter specs added but dialyzer still warns
  # on the do_http/6 struct type vs t() alias
  ~r/lib\/tokenio_client\/http\/client\.ex.*contract_supertype/,

  # decode_event returns a specific map shape, not plain map()
  ~r/lib\/tokenio_client\/webhooks\.ex.*contract_supertype/
]
