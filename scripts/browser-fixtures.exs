defmodule FogOfWar.BrowserFixtures do
  @moduledoc false
  import Plug.Conn
  @endpoint FogOfWarBasicWeb.Endpoint
  @root Path.expand("..", __DIR__)

  def init(opts), do: opts

  def call(%{request_path: "/__fog_of_war_test__/live-bundle"} = conn, _) do
    # Build-time capture, deliberately separate from the browser's empty data store.
    # Preserve the complete LiveView document/client; discard response cookies only.
    pages =
      Map.new(["/", "/counters/one", "/counters/two", "/counters/three"], fn path ->
        rendered =
          Plug.Test.conn(:get, path)
          |> Map.put(:host, "127.0.0.1")
          |> Map.put(:port, 47183)
          |> put_req_header("x-fog-of-war-test-session", "expired")
          |> call([])

        {path, IO.iodata_to_binary(rendered.resp_body)}
      end)

    paths =
      Enum.flat_map(pages, fn {_, html} ->
        html
        |> Floki.parse_document!()
        |> Floki.find("script[src],link[href]")
        |> Enum.flat_map(fn {_, attrs, _} ->
          for {key, value} <- attrs, key in ["src", "href"], do: URI.parse(value).path
        end)
      end)
      |> Enum.uniq()

    assets =
      Map.new(paths, fn path ->
        unless path in ["/assets/js/app.js", "/css/app.css", "/favicon.ico"],
          do: raise("Review new bundled test asset: #{path}")

        bytes = File.read!(Path.join(@root, "examples/basic/priv/static" <> path))
        {path, %{body: Base.encode64(bytes), content_type: MIME.from_path(path)}}
      end)

    id = Integer.to_string(System.unique_integer([:positive]))
    :persistent_term.put({__MODULE__, :bundle, id}, pages)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      200,
      Jason.encode!(%{
        pages: pages,
        assets: assets,
        signed_age_days: 30,
        token_verdict: "expired",
        response_cookies_included: false,
        bundle_id: id
      })
    )
  end

  def call(%{request_path: "/__fog_of_war_test__/backend"} = conn, _) do
    conn = fetch_query_params(conn)
    :persistent_term.put({__MODULE__, :backend_down}, conn.query_params["down"] == "true")
    conn |> put_resp_content_type("application/json") |> send_resp(200, "{}")
  end

  def call(%{request_path: "/__fog_of_war_test__/startup"} = conn, _) do
    bundle =
      Path.join(@root, "test/browser/fixtures/public-bundle.json")
      |> File.read!()
      |> Jason.decode!()

    css = File.read!(Path.join(@root, "examples/basic/priv/static/css/app.css"))
    model = File.read!(Path.join(@root, "test/browser/support/startup-model.js"))
    # JSON is in an executable script element here; escape closing-tag delimiters.
    data = Jason.encode!(%{pages: bundle["pages"], css: css}) |> String.replace("<", "\\u003c")

    body = """
    <!doctype html><html><head><meta charset="utf-8"><title>Startup policy model</title>
    <style>html,body{margin:0;height:100%;background:#f5f7f3}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}#candidate{opacity:0;pointer-events:none}</style></head>
    <body data-presentation="cached"><iframe id="cached" title="Cached public page"></iframe>
    <script>window.startupFixture=#{data};</script><script>#{model}</script></body></html>
    """

    conn |> put_resp_content_type("text/html") |> send_resp(200, body)
  end

  def call(conn, _) do
    case get_req_header(conn, "x-fog-of-war-test-bundle") do
      [id] ->
        pages = :persistent_term.get({__MODULE__, :bundle, id})

        conn
        |> put_resp_content_type("text/html")
        |> put_resp_header("x-fog-of-war-render-source", "bundle")
        |> send_resp(200, Map.fetch!(pages, conn.request_path))

      [] ->
        if String.starts_with?(conn.request_path, "/live/") &&
             :persistent_term.get({__MODULE__, :backend_down}, false) do
          send_resp(conn, 503, "Test backend unavailable")
        else
          call_endpoint(conn)
        end
    end
  end

  defp call_endpoint(conn) do
    variant = get_req_header(conn, "x-fog-of-war-test-session") |> List.first()
    iframe? = get_req_header(conn, "sec-fetch-dest") == ["iframe"]

    conn =
      register_before_send(conn, fn conn ->
        if String.starts_with?(
             get_resp_header(conn, "content-type") |> List.first() || "",
             "text/html"
           ) do
          conn = %{conn | resp_body: IO.iodata_to_binary(conn.resp_body)}

          conn =
            case variant do
              "expired" ->
                body =
                  Regex.replace(
                    ~r/(data-phx-(?:session|static)=")([^"]+)(")/,
                    conn.resp_body,
                    fn _, prefix, token, suffix ->
                      salt = Phoenix.LiveView.Utils.salt!(@endpoint)

                      {:ok, decoded} =
                        Phoenix.Token.verify(@endpoint, salt, token, max_age: :infinity)

                      expired =
                        Phoenix.Token.sign(@endpoint, salt, decoded,
                          signed_at: System.os_time(:second) - 30 * 86_400
                        )

                      {:error, :expired} =
                        Phoenix.LiveView.Static.verify_token(@endpoint, expired)

                      {:ok, ^decoded} =
                        Phoenix.Token.verify(@endpoint, salt, expired, max_age: :infinity)

                      prefix <> expired <> suffix
                    end
                  )

                %{conn | resp_body: body}
                |> put_resp_header("x-fog-of-war-token-verdict", "expired")

              "missing-cookie" ->
                %{conn | resp_cookies: %{}} |> delete_resp_header("set-cookie")

              "mismatched-csrf" ->
                body =
                  Regex.replace(
                    ~r/(<meta name="csrf-token" content=")[^"]+("[^>]*>)/,
                    conn.resp_body,
                    "\\1not-the-cookie-csrf-value\\2"
                  )

                %{conn | resp_body: body}

              _ ->
                conn
            end

          if iframe? do
            bridge = """
            <script>window.addEventListener('fog-of-war:snapshot',()=>{
              const region=document.querySelector('[phx-hook="FogOfWar"]');
              parent.postMessage({kind:'fog-of-war-test-root-mounted',attempt:window.name,path:region?.dataset.fogOfWarPath},location.origin);
            });</script>
            """

            %{conn | resp_body: String.replace(conn.resp_body, "</head>", bridge <> "</head>")}
          else
            conn
          end
        else
          conn
        end
      end)

    @endpoint.call(conn, @endpoint.init([]))
  end
end
