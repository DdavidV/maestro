defmodule Maestro.Clients.HttpTest do
  use ExUnit.Case, async: true

  alias Maestro.Clients.Http

  defmodule TransportHooks do
    def add_header(%Req.Request{} = req, name, value) do
      Req.Request.put_header(req, name, value)
    end

    def not_a_request(%Req.Request{} = _req), do: "not a Req.Request"
    def boom(%Req.Request{} = _req), do: raise("kaboom")

    def conflicting_finch_and_connect_options(%Req.Request{} = req) do
      Req.merge(req, connect_options: [timeout: 1000])
    end
  end

  setup_all do
    port = 45_678
    {:ok, _pid} = Bandit.start_link(plug: Maestro.TestHttpPlug, port: port, scheme: :http)
    {:ok, %{state: client_state}} = Maestro.Client.Registry.fetch("http")
    %{base: "http://localhost:#{port}", client_state: client_state}
  end

  defp do_send(client_state, options, payload \\ %{}) do
    Http.send(client_state, %{"payload" => payload, "options" => options})
  end

  describe "method and url" do
    test "defaults to GET when method is omitted", %{base: base, client_state: cs} do
      assert {:ok, %{"body" => %{"method" => "GET"}}} = do_send(cs, %{"url" => "#{base}/echo"})
    end

    test "method is case-insensitive", %{base: base, client_state: cs} do
      assert {:ok, %{"body" => %{"method" => "POST"}}} =
               do_send(cs, %{"method" => "post", "url" => "#{base}/echo"})
    end

    test "an unresolvable/invalid url is a clean error, not a crash", %{client_state: cs} do
      assert do_send(cs, %{"url" => "not-a-url"}) == {:error, {:invalid_url, "not-a-url"}}

      assert do_send(cs, %{"url" => "ftp://example.com"}) ==
               {:error, {:invalid_url, "ftp://example.com"}}
    end

    test "a missing url is a clean error", %{client_state: cs} do
      assert do_send(cs, %{}) == {:error, :missing_url}
    end

    test "connection refused is a clean error, not a crash", %{client_state: cs} do
      assert {:error, {:request_failed, _reason}} = do_send(cs, %{"url" => "http://localhost:1/"})
    end
  end

  describe "payload as request body" do
    test "a map payload is sent as a JSON body with content-type set", %{
      base: base,
      client_state: cs
    } do
      assert {:ok, %{"body" => body}} =
               do_send(cs, %{"method" => "POST", "url" => "#{base}/echo"}, %{"foo" => "bar"})

      assert body["payload"] == %{"foo" => "bar"}
      assert body["headers"]["content-type"] == "application/json"
    end

    test "an empty map payload sends no body", %{base: base, client_state: cs} do
      assert {:ok, %{"body" => body}} =
               do_send(cs, %{"method" => "POST", "url" => "#{base}/echo"}, %{})

      assert body["payload"] == nil
    end
  end

  describe "headers and query" do
    test "custom headers are sent through", %{base: base, client_state: cs} do
      assert {:ok, %{"body" => body}} =
               do_send(cs, %{"url" => "#{base}/echo", "headers" => %{"X-Custom" => "abc"}})

      assert body["headers"]["x-custom"] == "abc"
    end

    test "an explicit content-type header is not overridden", %{base: base, client_state: cs} do
      assert {:ok, %{"body" => body}} =
               do_send(
                 cs,
                 %{
                   "method" => "POST",
                   "url" => "#{base}/echo",
                   "headers" => %{"content-type" => "application/json; charset=utf-8"}
                 },
                 %{"a" => 1}
               )

      assert body["headers"]["content-type"] == "application/json; charset=utf-8"
    end

    test "query params are merged into the request", %{base: base, client_state: cs} do
      assert {:ok, %{"body" => body}} =
               do_send(cs, %{"url" => "#{base}/echo", "query" => %{"expand" => "items"}})

      assert body["query"] == %{"expand" => "items"}
    end
  end

  describe "response shape" do
    test "status is surfaced as an integer", %{base: base, client_state: cs} do
      assert {:ok, %{"status" => 201}} = do_send(cs, %{"url" => "#{base}/status/201"})
      assert {:ok, %{"status" => 404}} = do_send(cs, %{"url" => "#{base}/status/404"})
    end

    test "a JSON response body is decoded into a map", %{base: base, client_state: cs} do
      assert {:ok, %{"body" => body}} = do_send(cs, %{"url" => "#{base}/echo"})
      assert is_map(body)
    end

    test "a non-JSON response body is returned as a raw string", %{base: base, client_state: cs} do
      assert {:ok, %{"body" => "hello world"}} = do_send(cs, %{"url" => "#{base}/text"})
    end

    test "headers are grouped as name to list-of-values", %{base: base, client_state: cs} do
      assert {:ok, %{"headers" => headers}} = do_send(cs, %{"url" => "#{base}/echo"})
      assert %{"content-type" => ["application/json" <> _]} = headers
    end
  end

  describe "timeout" do
    test "a request exceeding timeout is a clean error, not a crash", %{
      base: base,
      client_state: cs
    } do
      assert do_send(cs, %{"url" => "#{base}/slow", "timeout" => 100}) ==
               {:error, {:request_failed, "timeout"}}
    end
  end

  describe "malformed options" do
    test "a non-string method is a clean error", %{base: base, client_state: cs} do
      assert do_send(cs, %{"method" => 1, "url" => "#{base}/echo"}) ==
               {:error, {:invalid_method, 1}}
    end

    test "a non-map headers is a clean error", %{base: base, client_state: cs} do
      assert do_send(cs, %{"url" => "#{base}/echo", "headers" => "nope"}) ==
               {:error, {:invalid_headers, "nope"}}
    end

    test "a non-integer timeout is a clean error", %{base: base, client_state: cs} do
      assert do_send(cs, %{"url" => "#{base}/echo", "timeout" => "slow"}) ==
               {:error, {:invalid_timeout, "slow"}}
    end
  end

  describe "transport_mfa" do
    test "modifies the outgoing request via the returned Req.Request", %{
      base: base,
      client_state: cs
    } do
      options = %{
        "url" => "#{base}/echo",
        "transport_mfa" => %{
          "module" => "Maestro.Clients.HttpTest.TransportHooks",
          "function" => "add_header",
          "args" => ["x-via-transport", "abc"]
        }
      }

      assert {:ok, %{"body" => body}} = do_send(cs, options)
      assert body["headers"]["x-via-transport"] == "abc"
    end

    test "omitted transport_mfa is a no-op", %{base: base, client_state: cs} do
      assert {:ok, %{"status" => 200}} = do_send(cs, %{"url" => "#{base}/echo"})
    end

    test "a function not returning a Req.Request is a clean error", %{
      base: base,
      client_state: cs
    } do
      options = %{
        "url" => "#{base}/echo",
        "transport_mfa" => %{
          "module" => "Maestro.Clients.HttpTest.TransportHooks",
          "function" => "not_a_request"
        }
      }

      assert do_send(cs, options) ==
               {:error,
                {:invalid_transport_mfa_result, Maestro.Clients.HttpTest.TransportHooks,
                 :not_a_request, "not a Req.Request"}}
    end

    test "an unknown module never crashes the run", %{base: base, client_state: cs} do
      options = %{
        "url" => "#{base}/echo",
        "transport_mfa" => %{"module" => "Does.Not.Exist", "function" => "add_header"}
      }

      assert do_send(cs, options) == {:error, {:mfa_module_not_found, "Does.Not.Exist"}}
    end

    test "a raising function is rescued, not a crash", %{base: base, client_state: cs} do
      options = %{
        "url" => "#{base}/echo",
        "transport_mfa" => %{
          "module" => "Maestro.Clients.HttpTest.TransportHooks",
          "function" => "boom"
        }
      }

      assert do_send(cs, options) ==
               {:error, {:mfa_raised, Maestro.Clients.HttpTest.TransportHooks, :boom, "kaboom"}}
    end

    test "a malformed transport_mfa directive is a clean error", %{
      base: base,
      client_state: cs
    } do
      options = %{"url" => "#{base}/echo", "transport_mfa" => %{"module" => "OnlyModule"}}

      assert do_send(cs, options) ==
               {:error, {:invalid_transport_mfa_directive, %{"module" => "OnlyModule"}}}
    end

    test "a Req.Request that raises once Req processes it is a clean error, not a crash", %{
      base: base,
      client_state: cs
    } do
      options = %{
        "url" => "#{base}/echo",
        "transport_mfa" => %{
          "module" => "Maestro.Clients.HttpTest.TransportHooks",
          "function" => "conflicting_finch_and_connect_options"
        }
      }

      assert {:error, {:invalid_transport_config, _reason}} = do_send(cs, options)
    end
  end

  describe "connection pool configuration" do
    test "init_client/0 passes config :maestro, :http_pool_options through to Finch.start_link, forcing :name" do
      Application.put_env(:maestro, :http_pool_options,
        name: :should_be_overridden,
        pools: %{default: [size: 3, count: 1]}
      )

      on_exit(fn -> Application.delete_env(:maestro, :http_pool_options) end)

      pool_options = Application.get_env(:maestro, :http_pool_options, [])
      opts = Keyword.put(pool_options, :name, Maestro.Clients.HttpTest.CustomPool)

      assert opts[:name] == Maestro.Clients.HttpTest.CustomPool
      assert opts[:pools] == %{default: [size: 3, count: 1]}

      assert {:ok, pid} = Finch.start_link(opts)
      assert Process.alive?(pid)
      Supervisor.stop(pid)
    end

    test "defaults to [] (Finch's own defaults) when unset" do
      assert Application.get_env(:maestro, :http_pool_options, []) == []
    end

    test "the registered client_state names the pool it started, not just a bare pid", %{
      client_state: cs
    } do
      assert %{finch_name: Http.Finch, finch_pid: pid} = cs
      assert Process.alive?(pid)
    end
  end

  describe "registration" do
    test "is discoverable under the name \"http\"" do
      assert Http.name() == "http"
      assert {:ok, %{module: Http}} = Maestro.Client.Registry.fetch("http")
    end
  end
end
