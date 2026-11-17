defmodule FogOfWar.AccountKeyEndpoint do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with %{"device_id" => device_id} when is_binary(device_id) <- conn.body_params,
         true <- byte_size(device_id) == 36,
         true <-
           Regex.match?(
             ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i,
             device_id
           ),
         {module, function} <- Application.get_env(:fow, :account_key_identity),
         scope when is_binary(scope) and scope != "" <- apply(module, function, [conn]),
         secret when is_binary(secret) and byte_size(secret) >= 32 <- conn.secret_key_base do
      dedicated = :crypto.mac(:hmac, :sha256, secret, "fow-account-cache-server")
      key = FogOfWar.AccountKey.derive!(dedicated, scope, device_id)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{user_id: scope, key: key}))
    else
      _ -> send_resp(conn, 403, "")
    end
  end
end
