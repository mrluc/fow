defmodule FogOfWar.AccountKeyEndpointTest do
  use ExUnit.Case, async: false

  alias FogOfWar.AccountKeyEndpoint

  def scope(conn), do: conn.assigns[:account_scope]

  test "the endpoint derives the key from the authenticated scope, not the request body" do
    previous = Application.fetch_env(:fow, :account_key_identity)
    Application.put_env(:fow, :account_key_identity, {__MODULE__, :scope})

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:fow, :account_key_identity, value)
        :error -> Application.delete_env(:fow, :account_key_identity)
      end
    end)

    request =
      Plug.Test.conn(:post, "/_fow/account-key", %{
        "user_id" => "other",
        "device_id" => "1555dedd-8ddd-4e24-8f46-b428724f1fa3"
      })
      |> Map.put(:secret_key_base, String.duplicate("s", 64))

    assert AccountKeyEndpoint.call(request, []).status == 403

    response =
      request
      |> Plug.Conn.assign(:account_scope, "tenant:alice")
      |> AccountKeyEndpoint.call([])

    assert response.status == 200
    assert Plug.Conn.get_resp_header(response, "cache-control") == ["no-store"]
    assert %{"user_id" => "tenant:alice", "key" => key} = Jason.decode!(response.resp_body)
    assert byte_size(Base.decode64!(key)) == 32
  end
end
