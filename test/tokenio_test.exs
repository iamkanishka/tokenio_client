defmodule TokenioClientTest do
  use ExUnit.Case, async: true

  describe "new/1" do
    test "accepts oauth2 credentials" do
      assert {:ok, client} = TokenioClient.new(client_id: "id", client_secret: "secret")
      assert client.http.auth == {:oauth2, "id", "secret"}
    end

    test "accepts static token" do
      assert {:ok, client} = TokenioClient.new(static_token: "tok")
      assert client.http.auth == {:static, "tok"}
    end

    test "defaults to sandbox environment" do
      assert {:ok, client} = TokenioClient.new(static_token: "tok")
      assert client.http.base_url == "https://api.sandbox.token.io"
    end

    test "production environment" do
      assert {:ok, client} = TokenioClient.new(static_token: "tok", environment: :production)
      assert client.http.base_url == "https://api.token.io"
    end

    test "custom base_url overrides environment" do
      assert {:ok, client} =
               TokenioClient.new(static_token: "tok", base_url: "http://localhost:4000")

      assert client.http.base_url == "http://localhost:4000"
    end

    test "returns error when no credentials given" do
      assert {:error, %TokenioClient.Error{code: :unknown}} = TokenioClient.new([])
    end

    test "returns error for empty static_token" do
      assert {:error, %TokenioClient.Error{code: :unknown}} = TokenioClient.new(static_token: "")
    end

    test "applies custom timeout and max_retries" do
      assert {:ok, client} =
               TokenioClient.new(static_token: "tok", timeout: 60_000, max_retries: 5)

      assert client.http.timeout == 60_000
      assert client.http.max_retries == 5
    end
  end

  describe "new!/1" do
    test "returns client on success" do
      assert %TokenioClient.Client{} = TokenioClient.new!(static_token: "tok")
    end

    test "raises TokenioClient.Error on missing credentials" do
      assert_raise TokenioClient.Error, fn -> TokenioClient.new!([]) end
    end
  end

  describe "version/0" do
    test "returns a non-empty string" do
      assert is_binary(TokenioClient.version())
      assert TokenioClient.version() != ""
    end
  end
end

# =============================================================================

defmodule TokenioClient.ErrorTest do
  use ExUnit.Case, async: true

  alias TokenioClient.Error

  describe "from_response/4" do
    test "maps 404 to :not_found" do
      err = Error.from_response(404, %{"code" => "NOT_FOUND", "message" => "not found"}, nil, nil)
      assert err.code == :not_found
      assert err.status == 404
      assert err.message == "not found"
    end

    test "maps 429 to :rate_limit_exceeded with retry_after" do
      err = Error.from_response(429, %{}, nil, "30")
      assert err.code == :rate_limit_exceeded
      assert err.retry_after == 30
    end

    test "maps 401 to :unauthorized, preserves request_id" do
      err = Error.from_response(401, %{}, "trace-abc", nil)
      assert err.code == :unauthorized
      assert err.request_id == "trace-abc"
    end

    test "prefers API code over HTTP status inference" do
      err =
        Error.from_response(400, %{"code" => "VALIDATION_ERROR", "message" => "bad"}, nil, nil)

      assert err.code == :validation_error
      assert err.message == "bad"
    end

    test "falls back to default message when message absent" do
      err = Error.from_response(503, %{}, nil, nil)
      assert err.message != ""
    end

    test "maps 502 to :bad_gateway" do
      err = Error.from_response(502, %{}, nil, nil)
      assert err.code == :bad_gateway
    end

    test "maps 500 to :internal_server_error" do
      err = Error.from_response(500, %{}, nil, nil)
      assert err.code == :internal_server_error
    end

    test "maps unknown status to :unknown" do
      err = Error.from_response(418, %{}, nil, nil)
      assert err.code == :unknown
    end

    test "ignores non-integer retry_after header" do
      err = Error.from_response(429, %{}, nil, "soon")
      assert err.retry_after == nil
    end
  end

  describe "predicates" do
    test "retryable?/1 — true for 429 500 502 503 504" do
      for status <- [429, 500, 502, 503, 504] do
        assert Error.retryable?(%Error{code: :unknown, message: "", status: status})
      end
    end

    test "retryable?/1 — false for 400 401 403 404" do
      for status <- [400, 401, 403, 404, 422] do
        refute Error.retryable?(%Error{code: :unknown, message: "", status: status})
      end
    end

    test "not_found?/1" do
      assert Error.not_found?(%Error{code: :not_found, message: "", status: 404})
      refute Error.not_found?(%Error{code: :unauthorized, message: "", status: 401})
    end

    test "unauthorized?/1" do
      assert Error.unauthorized?(%Error{code: :unauthorized, message: "", status: 401})
      refute Error.unauthorized?(%Error{code: :not_found, message: "", status: 404})
    end

    test "rate_limited?/1" do
      assert Error.rate_limited?(%Error{code: :rate_limit_exceeded, message: "", status: 429})
      refute Error.rate_limited?(%Error{code: :not_found, message: "", status: 404})
    end
  end

  describe "Exception.message/1" do
    test "includes code, message, status, and trace_id" do
      err = %Error{code: :not_found, message: "Payment not found", status: 404, request_id: "r1"}
      msg = Exception.message(err)
      assert msg =~ "not_found"
      assert msg =~ "404"
      assert msg =~ "r1"
    end

    test "omits trace_id when nil" do
      err = %Error{code: :unauthorized, message: "Bad token", status: 401}
      msg = Exception.message(err)
      assert msg =~ "unauthorized"
      refute msg =~ "trace_id"
    end
  end
end

# =============================================================================

defmodule TokenioClient.Payments.PaymentTest do
  use ExUnit.Case, async: true

  alias TokenioClient.Payments.Payment

  @raw_completed %{
    "id" => "pm:abc:def",
    "status" => "INITIATION_COMPLETED",
    "createdDateTime" => "2024-01-15T10:00:00Z",
    "updatedDateTime" => "2024-01-15T10:01:00Z"
  }

  @raw_redirect %{
    "id" => "pm:abc:123",
    "status" => "INITIATION_PENDING_REDIRECT_AUTH",
    "authentication" => %{"redirectUrl" => "https://bank.example.com/auth?t=xyz"}
  }

  @raw_embedded %{
    "id" => "pm:abc:456",
    "status" => "INITIATION_PENDING_EMBEDDED_AUTH",
    "authentication" => %{
      "embeddedAuth" => [
        %{"id" => "otp", "type" => "OTP", "displayName" => "OTP Code", "mandatory" => true}
      ]
    }
  }

  describe "from_map/1" do
    test "parses completed payment" do
      p = Payment.from_map(@raw_completed)
      assert p.id == "pm:abc:def"
      assert p.status == "INITIATION_COMPLETED"
      assert %DateTime{year: 2024} = p.created_at
    end

    test "extracts redirect URL" do
      p = Payment.from_map(@raw_redirect)
      assert p.redirect_url == "https://bank.example.com/auth?t=xyz"
    end

    test "extracts embedded auth fields" do
      p = Payment.from_map(@raw_embedded)
      assert p.embedded_auth_fields != []
      [f] = p.embedded_auth_fields
      assert f.id == "otp"
      assert f.mandatory == true
    end

    test "returns nil for nil input" do
      assert Payment.from_map(nil) == nil
    end
  end

  describe "final?/1" do
    test "terminal statuses return true" do
      for s <- ~w[INITIATION_COMPLETED INITIATION_REJECTED INITIATION_REJECTED_INSUFFICIENT_FUNDS
                  INITIATION_FAILED INITIATION_DECLINED INITIATION_EXPIRED
                  INITIATION_NO_FINAL_STATUS_AVAILABLE SETTLEMENT_COMPLETED
                  SETTLEMENT_INCOMPLETE CANCELED] do
        assert Payment.final?(%Payment{status: s}), "expected #{s} to be final"
      end
    end

    test "non-terminal statuses return false" do
      for s <- ~w[INITIATION_PENDING INITIATION_PENDING_REDIRECT_AUTH
                  INITIATION_PROCESSING SETTLEMENT_IN_PROGRESS] do
        refute Payment.final?(%Payment{status: s}), "expected #{s} NOT to be final"
      end
    end
  end

  describe "requires_redirect?/1" do
    test "redirect statuses return true" do
      for s <- ~w[INITIATION_PENDING_REDIRECT_AUTH INITIATION_PENDING_REDIRECT_HP
                  INITIATION_PENDING_REDIRECT_PBL] do
        assert Payment.requires_redirect?(%Payment{status: s})
      end
    end

    test "other statuses return false" do
      refute Payment.requires_redirect?(%Payment{status: "INITIATION_PENDING"})
    end
  end

  describe "requires_embedded_auth?/1" do
    test "returns true for embedded auth status" do
      assert Payment.requires_embedded_auth?(%Payment{status: "INITIATION_PENDING_EMBEDDED_AUTH"})
    end

    test "returns false otherwise" do
      refute Payment.requires_embedded_auth?(%Payment{status: "INITIATION_PENDING"})
    end
  end

  describe "completed?/1" do
    test "true for INITIATION_COMPLETED and SETTLEMENT_COMPLETED" do
      assert Payment.completed?(%Payment{status: "INITIATION_COMPLETED"})
      assert Payment.completed?(%Payment{status: "SETTLEMENT_COMPLETED"})
    end

    test "false for failed payment" do
      refute Payment.completed?(%Payment{status: "INITIATION_FAILED"})
    end
  end

  describe "failed?/1" do
    test "true for failure statuses" do
      for s <- ~w[INITIATION_FAILED INITIATION_REJECTED INITIATION_DECLINED] do
        assert Payment.failed?(%Payment{status: s})
      end
    end

    test "false for completed payment" do
      refute Payment.failed?(%Payment{status: "INITIATION_COMPLETED"})
    end
  end
end

# =============================================================================

defmodule TokenioClient.VRP.ConsentTest do
  use ExUnit.Case, async: true

  alias TokenioClient.VRP.Consent

  describe "from_map/1" do
    test "parses consent" do
      m = %{
        "id" => "vc:abc",
        "status" => "AUTHORIZED",
        "createdDateTime" => "2024-01-01T00:00:00Z"
      }

      c = Consent.from_map(m)
      assert c.id == "vc:abc"
      assert c.status == "AUTHORIZED"
      assert %DateTime{} = c.created_at
    end

    test "extracts redirect URL" do
      m = %{
        "id" => "vc:1",
        "status" => "PENDING_REDIRECT_AUTH",
        "authentication" => %{"redirectUrl" => "https://bank.example.com"}
      }

      c = Consent.from_map(m)
      assert c.redirect_url == "https://bank.example.com"
    end
  end

  describe "status predicates" do
    test "final?/1" do
      for s <- ~w[AUTHORIZED REJECTED REVOKED FAILED] do
        assert Consent.final?(%Consent{status: s})
      end

      refute Consent.final?(%Consent{status: "PENDING"})
    end

    test "authorized?/1" do
      assert Consent.authorized?(%Consent{status: "AUTHORIZED"})
      refute Consent.authorized?(%Consent{status: "PENDING"})
    end

    test "requires_redirect?/1" do
      assert Consent.requires_redirect?(%Consent{status: "PENDING_REDIRECT_AUTH"})
      refute Consent.requires_redirect?(%Consent{status: "PENDING"})
    end
  end
end

# =============================================================================

defmodule TokenioClient.TypesTest do
  use ExUnit.Case, async: true

  alias TokenioClient.Types

  describe "Amount.from_map/1" do
    test "parses correctly" do
      a = Types.Amount.from_map(%{"value" => "10.50", "currency" => "GBP"})
      assert a.value == "10.50"
      assert a.currency == "GBP"
    end

    test "returns nil for nil" do
      assert Types.Amount.from_map(nil) == nil
    end
  end

  describe "PageInfo.from_map/1" do
    test "parses pagination info" do
      p = Types.PageInfo.from_map(%{"limit" => 20, "nextOffset" => "abc", "haveMore" => true})
      assert p.limit == 20
      assert p.next_offset == "abc"
      assert p.have_more == true
    end

    test "defaults have_more to false" do
      p = Types.PageInfo.from_map(%{"limit" => 10})
      assert p.have_more == false
    end

    test "returns nil for nil" do
      assert Types.PageInfo.from_map(nil) == nil
    end
  end

  describe "parse_datetime/1" do
    test "parses ISO 8601 UTC string" do
      dt = Types.parse_datetime("2024-01-15T10:30:00Z")
      assert %DateTime{year: 2024, month: 1, day: 15} = dt
    end

    test "returns nil for nil" do
      assert Types.parse_datetime(nil) == nil
    end

    test "returns nil for empty string" do
      assert Types.parse_datetime("") == nil
    end

    test "returns nil for invalid string" do
      assert Types.parse_datetime("not-a-date") == nil
    end
  end

  describe "PartyAccount.from_map/1" do
    test "parses all fields" do
      m = %{
        "iban" => "GB29NWBK60161331926819",
        "bic" => "NWBKGB2L",
        "name" => "Acme Ltd",
        "accountNumber" => "31926819",
        "sortCode" => "601613"
      }

      a = Types.PartyAccount.from_map(m)
      assert a.iban == "GB29NWBK60161331926819"
      assert a.name == "Acme Ltd"
      assert a.account_number == "31926819"
      assert a.sort_code == "601613"
    end
  end

  describe "encode_amount/1" do
    test "encodes atom-keyed map" do
      m = Types.encode_amount(%{value: "10.00", currency: "GBP"})
      assert m == %{"value" => "10.00", "currency" => "GBP"}
    end

    test "passes through string-keyed map" do
      m = Types.encode_amount(%{"value" => "5.00", "currency" => "EUR"})
      assert m == %{"value" => "5.00", "currency" => "EUR"}
    end

    test "returns nil for nil" do
      assert Types.encode_amount(nil) == nil
    end
  end
end

# =============================================================================

defmodule TokenioClient.WebhooksTest do
  use ExUnit.Case, async: true

  alias TokenioClient.Webhooks

  # Non-production test secret — safe to commit per gosec equivalent in Elixir.
  @test_secret "tokenio_client-test-webhook-secret-for-unit-tests-only"

  defp make_sig(secret, payload) do
    ts = System.os_time(:second)
    signed = "#{ts}.#{payload}"
    hex = Base.encode16(:crypto.mac(:hmac, :sha256, secret, signed), case: :lower)
    {"t=#{ts},v1=#{hex}", ts}
  end

  describe "parse/3" do
    test "accepts valid HMAC signature and returns event" do
      payload =
        Jason.encode!(%{
          "id" => "evt-001",
          "type" => "payment.updated",
          "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "data" => %{"paymentId" => "pm:abc", "status" => "INITIATION_COMPLETED"}
        })

      {sig, _ts} = make_sig(@test_secret, payload)

      assert {:ok, event} = Webhooks.parse(payload, sig, webhook_secret: @test_secret)
      assert event.id == "evt-001"
      assert event.type == "payment.updated"
      assert event.data["paymentId"] == "pm:abc"
    end

    test "rejects invalid signature" do
      payload = ~s({"id":"evt","type":"payment.updated","createdAt":"2024-01-01T00:00:00Z"})
      ts = System.os_time(:second)
      bad_sig = "t=#{ts},v1=0000000000000000000000000000000000000000000000000000000000000000"

      assert {:error, :invalid_signature} =
               Webhooks.parse(payload, bad_sig, webhook_secret: @test_secret)
    end

    test "rejects stale timestamp" do
      payload = ~s({"id":"stale"})
      old_ts = System.os_time(:second) - 400
      signed = "#{old_ts}.#{payload}"
      hex = Base.encode16(:crypto.mac(:hmac, :sha256, @test_secret, signed), case: :lower)
      stale_sig = "t=#{old_ts},v1=#{hex}"

      assert {:error, :stale_timestamp} =
               Webhooks.parse(payload, stale_sig, webhook_secret: @test_secret)
    end

    test "rejects malformed signature header" do
      payload = ~s({"id":"x"})
      opts = [webhook_secret: @test_secret]
      assert {:error, :malformed_signature} = Webhooks.parse(payload, "bad", opts)
      assert {:error, :malformed_signature} = Webhooks.parse(payload, nil, opts)
      assert {:error, :malformed_signature} = Webhooks.parse(payload, "", opts)
    end

    test "skips verification when secret is nil" do
      payload =
        Jason.encode!(%{
          "id" => "evt-2",
          "type" => "vrp.completed",
          "createdAt" => "2024-01-01T00:00:00Z"
        })

      assert {:ok, event} = Webhooks.parse(payload, "any", webhook_secret: nil)
      assert event.id == "evt-2"
    end

    test "returns json_decode_error for invalid JSON" do
      assert {:error, :json_decode_error} = Webhooks.parse("not json", nil, webhook_secret: nil)
    end
  end

  describe "typed event decoders" do
    test "decode_payment_data/1" do
      event = %{
        "data" => %{"paymentId" => "pm:abc", "status" => "COMPLETED", "memberId" => "m:1"}
      }

      d = Webhooks.decode_payment_data(event)
      assert d.payment_id == "pm:abc"
      assert d.status == "COMPLETED"
      assert d.member_id == "m:1"
    end

    test "decode_vrp_consent_data/1" do
      event = %{"data" => %{"consentId" => "vc:abc", "status" => "AUTHORIZED"}}
      d = Webhooks.decode_vrp_consent_data(event)
      assert d.consent_id == "vc:abc"
    end

    test "decode_vrp_data/1" do
      event = %{"data" => %{"vrpId" => "vrp:1", "consentId" => "vc:1", "status" => "COMPLETED"}}
      d = Webhooks.decode_vrp_data(event)
      assert d.vrp_id == "vrp:1"
      assert d.consent_id == "vc:1"
    end

    test "decode_refund_data/1" do
      event = %{"data" => %{"refundId" => "r:1", "transferId" => "t:1", "status" => "COMPLETED"}}
      d = Webhooks.decode_refund_data(event)
      assert d.refund_id == "r:1"
      assert d.transfer_id == "t:1"
    end

    test "decode_payout_data/1" do
      event = %{"data" => %{"payoutId" => "p:1", "status" => "COMPLETED"}}
      d = Webhooks.decode_payout_data(event)
      assert d.payout_id == "p:1"
    end
  end

  describe "event type constants" do
    test "payment_event_types returns non-empty list" do
      types = Webhooks.payment_event_types()
      assert types != []
      assert "payment.completed" in types
    end

    test "vrp_event_types returns non-empty list" do
      assert Webhooks.vrp_event_types() != []
    end
  end
end

# =============================================================================

defmodule TokenioClient.HTTP.TokenCacheTest do
  use ExUnit.Case, async: false

  alias TokenioClient.HTTP.TokenCache

  setup do
    # Start a fresh TokenCache for each test to avoid cross-test contamination
    pid = start_supervised!(TokenCache)
    {:ok, pid: pid}
  end

  test "fetch_fn called on first access" do
    ref = :counters.new(1, [])
    key = "client-#{:erlang.unique_integer()}"

    result =
      TokenCache.get_or_fetch(key, fn ->
        :counters.add(ref, 1, 1)
        {:ok, "tok-#{key}", 3600}
      end)

    assert {:ok, _token} = result
    assert :counters.get(ref, 1) == 1
  end

  test "second call returns cached token without calling fetch_fn again" do
    ref = :counters.new(1, [])
    key = "client-#{:erlang.unique_integer()}"

    fetch_fn = fn ->
      :counters.add(ref, 1, 1)
      {:ok, "cached-tok", 3600}
    end

    {:ok, tok1} = TokenCache.get_or_fetch(key, fetch_fn)
    {:ok, tok2} = TokenCache.get_or_fetch(key, fetch_fn)

    assert tok1 == tok2
    assert :counters.get(ref, 1) == 1
  end

  test "propagates fetch errors without caching" do
    key = "error-client-#{:erlang.unique_integer()}"

    result =
      TokenCache.get_or_fetch(key, fn ->
        {:error, %TokenioClient.Error{code: :unauthorized, message: "Bad creds", status: 401}}
      end)

    assert {:error, %TokenioClient.Error{code: :unauthorized}} = result
  end
end
