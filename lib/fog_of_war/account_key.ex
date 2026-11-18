defmodule FogOfWar.AccountKey do
  @moduledoc """
  Derives a stable cache key for an authenticated account on one browser device.

  Call this from an authenticated endpoint. Supply the account scope from the
  server session, including the tenant when account IDs are tenant-local.
  Return the key over HTTPS with `Cache-Control: no-store`.
  """

  @doc """
  Returns a base64-encoded AES-256 key. Supply a dedicated random server
  secret of at least 32 bytes and a stable browser-generated UUID.
  Changing the secret or version makes earlier snapshots unreadable.
  """
  def derive!(secret, account_scope, device_id, version \\ 1)

  def derive!(secret, account_scope, device_id, version)
      when is_binary(secret) and byte_size(secret) >= 32 and is_binary(account_scope) and account_scope != "" and
             is_binary(device_id) and is_integer(version) and version > 0 do
    if !Regex.match?(
         ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i,
         device_id
       ),
       do: raise(ArgumentError, "expected a random device UUID")

    context =
      Jason.encode!(["fow-account-cache", version, account_scope, String.downcase(device_id)])

    :hmac |> :crypto.mac(:sha256, secret, context) |> Base.encode64()
  end

  def derive!(_, _, _, _), do: raise(ArgumentError, "invalid account key inputs")
end
