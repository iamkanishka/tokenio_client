defmodule TokenioClient.IntegrationTest do
  use ExUnit.Case, async: true

  setup do
    bypass = Bypass.open()
    {:ok, client} = TokenioClient.new(static_token: "test-token", base_url: endpoint(bypass))
    {:ok, bypass: bypass, client: client}
  end

  defp endpoint(bypass), do: "http://localhost:#{bypass.port}"

  defp json_resp(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  # ---------------------------------------------------------------------------
  # Payments
  # ---------------------------------------------------------------------------

  describe "TokenioClient.Payments.initiate/2" do
    test "sends correct request and parses payment", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v2/payments", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["initiation"]["bankId"] == "ob-modelo"
        assert decoded["initiation"]["amount"]["value"] == "10.00"
        assert decoded["initiation"]["amount"]["currency"] == "GBP"

        json_resp(conn, 200, %{
          "payment" => %{
            "id" => "pm:abc:def",
            "status" => "INITIATION_PENDING_REDIRECT_AUTH",
            "authentication" => %{"redirectUrl" => "https://bank.example.com/auth"},
            "createdDateTime" => "2024-01-15T10:00:00Z",
            "updatedDateTime" => "2024-01-15T10:00:00Z"
          }
        })
      end)

      assert {:ok, payment} =
               TokenioClient.Payments.initiate(client, %{
                 bank_id: "ob-modelo",
                 amount: %{value: "10.00", currency: "GBP"},
                 creditor: %{account_number: "12345678", sort_code: "040004", name: "Acme"},
                 callback_url: "https://yourapp.com/return"
               })

      assert payment.id == "pm:abc:def"
      assert payment.status == "INITIATION_PENDING_REDIRECT_AUTH"
      assert payment.redirect_url == "https://bank.example.com/auth"
      assert TokenioClient.Payments.Payment.requires_redirect?(payment)
      refute TokenioClient.Payments.Payment.final?(payment)
    end

    test "returns validation_error on 400", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/v2/payments", fn conn ->
        json_resp(conn, 400, %{"code" => "VALIDATION_ERROR", "message" => "bankId required"})
      end)

      assert {:error, %TokenioClient.Error{code: :validation_error, status: 400}} =
               TokenioClient.Payments.initiate(client, %{})
    end
  end

  describe "TokenioClient.Payments.get/2" do
    test "retrieves payment by ID", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v2/payments/pm:abc", fn conn ->
        json_resp(conn, 200, %{
          "payment" => %{
            "id" => "pm:abc",
            "status" => "INITIATION_COMPLETED",
            "createdDateTime" => "2024-01-15T10:00:00Z",
            "updatedDateTime" => "2024-01-15T10:01:00Z"
          }
        })
      end)

      assert {:ok, payment} = TokenioClient.Payments.get(client, "pm:abc")
      assert payment.id == "pm:abc"
      assert TokenioClient.Payments.Payment.completed?(payment)
    end

    test "returns not_found for 404", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v2/payments/pm:missing", fn conn ->
        json_resp(conn, 404, %{"code" => "NOT_FOUND", "message" => "Payment not found"})
      end)

      assert {:error, %TokenioClient.Error{code: :not_found} = err} =
               TokenioClient.Payments.get(client, "pm:missing")

      assert TokenioClient.Error.not_found?(err)
    end

    test "returns validation error for empty payment_id", %{client: client} do
      assert {:error, %TokenioClient.Error{code: :unknown}} = TokenioClient.Payments.get(client, "")
    end
  end

  describe "TokenioClient.Payments.list/2" do
    test "sends correct query params", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v2/payments", fn conn ->
        params = URI.decode_query(conn.query_string)
        assert params["limit"] == "20"
        assert params["offset"] == "cursor123"

        json_resp(conn, 200, %{
          "payments" => [],
          "pageInfo" => %{"limit" => 20, "haveMore" => false}
        })
      end)

      assert {:ok, result} = TokenioClient.Payments.list(client, limit: 20, offset: "cursor123")
      assert result.payments == []
      assert result.page_info.limit == 20
    end

    test "returns error for invalid limit", %{client: client} do
      assert {:error, %TokenioClient.Error{}} = TokenioClient.Payments.list(client, limit: 0)
      assert {:error, %TokenioClient.Error{}} = TokenioClient.Payments.list(client, limit: 201)
    end
  end

  describe "TokenioClient.VRP.create_consent/2" do
    test "creates VRP consent with redirect", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/vrp-consents", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["initiation"]["bankId"] == "ob-modelo"
        assert decoded["initiation"]["currency"] == "GBP"

        json_resp(conn, 200, %{
          "vrpConsent" => %{
            "id" => "vc:abc",
            "status" => "PENDING",
            "createdDateTime" => "2024-01-15T10:00:00Z",
            "authentication" => %{"redirectUrl" => "https://bank.example.com/vrp-auth"}
          }
        })
      end)

      assert {:ok, consent} =
               TokenioClient.VRP.create_consent(client, %{
                 bank_id: "ob-modelo",
                 currency: "GBP",
                 creditor: %{account_number: "12345678", sort_code: "040004", name: "Acme"},
                 callback_url: "https://yourapp.com/vrp/return"
               })

      assert consent.id == "vc:abc"
      assert consent.redirect_url == "https://bank.example.com/vrp-auth"
    end
  end

  describe "TokenioClient.VRP.confirm_funds/3" do
    test "returns funds availability", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/vrps/vc:abc/confirm-funds", fn conn ->
        params = URI.decode_query(conn.query_string)
        assert params["amount"] == "49.99"
        json_resp(conn, 200, %{"fundsAvailable" => true})
      end)

      assert {:ok, true} = TokenioClient.VRP.confirm_funds(client, "vc:abc", "49.99")
    end
  end

  describe "TokenioClient.Banks.list_v2/2" do
    test "lists banks and parses response", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v2/banks", fn conn ->
        json_resp(conn, 200, %{
          "banks" => [
            %{
              "id" => "ob-modelo",
              "name" => "Modelo",
              "capabilities" => ["PIS", "AIS"],
              "enabled" => true
            }
          ],
          "pageInfo" => %{"limit" => 50, "haveMore" => false}
        })
      end)

      assert {:ok, result} = TokenioClient.Banks.list_v2(client, limit: 50)
      assert result.banks != []
      bank = hd(result.banks)
      assert bank.id == "ob-modelo"
      assert bank.enabled == true
    end
  end

  describe "TokenioClient.Webhooks config" do
    test "set_config sends PUT with URL", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PUT", "/webhook-config", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["config"]["url"] == "https://yourapp.com/hooks"
        json_resp(conn, 200, %{})
      end)

      assert :ok = TokenioClient.Webhooks.set_config(client, "https://yourapp.com/hooks")
    end

    test "get_config returns config map", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/webhook-config", fn conn ->
        json_resp(conn, 200, %{
          "config" => %{"url" => "https://yourapp.com/hooks", "events" => ["payment.completed"]}
        })
      end)

      assert {:ok, config} = TokenioClient.Webhooks.get_config(client)
      assert config["url"] == "https://yourapp.com/hooks"
    end
  end

  describe "AIS endpoints" do
    test "list_accounts returns accounts", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/accounts", fn conn ->
        json_resp(conn, 200, %{
          "accounts" => [
            %{"id" => "acc:1", "displayName" => "Current Account", "currency" => "GBP"}
          ],
          "pageInfo" => %{"limit" => 10, "haveMore" => false}
        })
      end)

      assert {:ok, result} = TokenioClient.AIS.list_accounts(client, limit: 10)
      assert result.accounts != []
      assert hd(result.accounts).id == "acc:1"
    end

    test "get_balance returns balance", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/accounts/acc:1/balance", fn conn ->
        json_resp(conn, 200, %{
          "balance" => %{
            "accountId" => "acc:1",
            "current" => %{"value" => "1234.56", "currency" => "GBP"}
          }
        })
      end)

      assert {:ok, balance} = TokenioClient.AIS.get_balance(client, "acc:1")
      assert balance.account_id == "acc:1"
      assert balance.current.value == "1234.56"
    end
  end

  describe "retry behaviour" do
    test "retries on 503 then succeeds", %{bypass: bypass} do
      {:ok, fast_client} =
        TokenioClient.new(
          static_token: "tok",
          base_url: endpoint(bypass),
          max_retries: 2,
          retry_wait_min: 10,
          retry_wait_max: 50
        )

      count = :counters.new(1, [])

      Bypass.expect(bypass, "GET", "/v2/payments/pm:retry", fn conn ->
        n = :counters.add(count, 1, 1)

        if :counters.get(count, 1) < 3 do
          _ = n
          json_resp(conn, 503, %{"code" => "SERVICE_UNAVAILABLE"})
        else
          json_resp(conn, 200, %{
            "payment" => %{
              "id" => "pm:retry",
              "status" => "INITIATION_COMPLETED",
              "createdDateTime" => "2024-01-01T00:00:00Z"
            }
          })
        end
      end)

      assert {:ok, payment} = TokenioClient.Payments.get(fast_client, "pm:retry")
      assert payment.id == "pm:retry"
      assert :counters.get(count, 1) == 3
    end

    test "does not retry on 400", %{bypass: bypass} do
      {:ok, retry_client} =
        TokenioClient.new(
          static_token: "tok",
          base_url: endpoint(bypass),
          max_retries: 3
        )

      count = :counters.new(1, [])

      Bypass.expect(bypass, "GET", "/v2/payments/pm:bad", fn conn ->
        :counters.add(count, 1, 1)
        json_resp(conn, 400, %{"code" => "VALIDATION_ERROR", "message" => "bad"})
      end)

      assert {:error, %TokenioClient.Error{code: :validation_error}} =
               TokenioClient.Payments.get(retry_client, "pm:bad")

      assert :counters.get(count, 1) == 1
    end
  end

  describe "Reports" do
    test "list_bank_statuses", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/bank-statuses", fn conn ->
        json_resp(conn, 200, %{
          "bankStatuses" => [
            %{"bankId" => "ob-modelo", "status" => "UP", "pisAvailable" => true}
          ]
        })
      end)

      assert {:ok, statuses} = TokenioClient.Reports.list_bank_statuses(client)
      assert statuses != []
      assert hd(statuses).bank_id == "ob-modelo"
      assert hd(statuses).pis_available == true
    end
  end

  describe "Verification" do
    test "initiates verification check", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/verification", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["bankId"] == "ob-modelo"
        assert decoded["account"]["accountNumber"] == "12345678"

        json_resp(conn, 200, %{
          "verification" => %{
            "id" => "ver:1",
            "status" => "PENDING",
            "createdDateTime" => "2024-01-01T00:00:00Z"
          }
        })
      end)

      assert {:ok, check} =
               TokenioClient.Verification.initiate(client, %{
                 bank_id: "ob-modelo",
                 account: %{account_number: "12345678", sort_code: "040004", name: "Test"}
               })

      assert check.id == "ver:1"
    end
  end
end
