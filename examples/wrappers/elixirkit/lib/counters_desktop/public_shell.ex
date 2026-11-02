defmodule CountersDesktop.PublicShell do
  @moduledoc "Serves only the exported public bundle on an ephemeral loopback port."
  use GenServer
  import Plug.Conn

  def start_link(_), do: GenServer.start_link(__MODULE__, :server, name: __MODULE__)
  def url, do: GenServer.call(__MODULE__, :url)
  def init(:server) do
    root = Application.app_dir(:counters_desktop, "priv/fog_of_war")
    bundle = root |> Path.join("bundle.json") |> File.read!() |> Jason.decode!()
    {:ok, listener} = Bandit.start_link(plug: {__MODULE__, {root, bundle}}, ip: {127, 0, 0, 1}, port: 0)
    {:ok, {_, port}} = ThousandIsland.listener_info(listener)
    url = "http://127.0.0.1:#{port}" <> bundle["start_path"]
    IO.puts("PUBLIC_SHELL_READY " <> url)
    {:ok, url}
  end
  def init(opts), do: opts
  def handle_call(:url, _, url), do: {:reply, url, url}
  def call(conn, {root, bundle}) do
    path = conn.request_path
    file = get_in(bundle, ["pages", path, "file"]) || bundle["assets"][path] ||
      if(path == "/_fog/bootstrap.js", do: "_fog/bootstrap.js")
    cond do
      conn.method not in ["GET", "HEAD"] -> send_resp(conn, 405, "Read-only public shell")
      is_nil(file) -> send_resp(conn, 404, "Not included in the public bundle")
      true ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_content_type(MIME.from_path(file))
        |> send_file(200, Path.join(root, file))
    end
  end
end
