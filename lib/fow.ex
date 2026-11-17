defmodule FogOfWar do
  @moduledoc """
  Adds read-only offline navigation to selected Phoenix LiveView pages.

  Start with `region/1`. It defines what FoW saves for a route and documents
  the options that configure the JavaScript capture hook.
  """
  use Phoenix.Component

  @doc """
  Wraps the routed content that Fog of War saves for offline navigation.

  Put one region at the top of each participating LiveView's rendered content.
  Include any navigation and content the user needs offline. Keep persistent
  controls such as `dev_tools/1` outside the region. FoW saves this section and
  its descendants after connected renders. Offline, it restores the saved HTML
  for the destination, and server actions will be disabled until the connection
  with the server comes back.

  ## Examples

  For a simple public page, where everyone will see the same data,
  wrap the routed content in a region.

      <FogOfWar.region>
        <.link navigate={~p"/"}>Back to index</.link>
        <output>{@detail}</output>
      </FogOfWar.region>

  Each time they visit that route, it's cached in the browser.

  **What about LiveViews with multiple users, though?** If Bob and Sally
  used the same open browser to sign in and sign out, they shouldn't
  see each other's cached content!

  Use `user-id` to save personalized markup:

      <FogOfWar.region
        user-id={@current_user && @current_user.id}
        require-user-id
      >
        <h1>Settings</h1>
        <p>{@current_user && @current_user.email}</p>
      </FogOfWar.region>

  **Note about security:** all markup is encrypted at rest on the client, to
  prevent low-effort IndexDB dumping style attacks, but it's not
  currently encrypted by a secret the *server* provides. So Bob and
  Sally, using the same browser and logging in and out, are not safe
  from each other! You can find the client secret and dump the other
  user's markup from a JS script in console.
  * In practice, as long as you know this, you can take it into account.
  * In the future, we will support a server provided per-user-device key,
    so a logged-out user's data is impenetrable to another user in this scenario.
    Since a login / logout usually requires the server anyway, this would be a natural
    place to refresh that.
  * However, this is relatively low priority. Why? Because an attack assumes
    users on the same device, or a remote compromise with the ability to eg.
    inject scripts into the browser. That's a lot of access, a lot worse
    things are likely possible on most people's computers / browsers, and it does
    require targeting this library, since bulk dumping only gives
    encrypted blobs.
  * Still, until harder guarantees exist, it may be good not to risk caching eg.
    sensitive information *at all* in the browser. Or, the offline mode
    could be opt-in to the users, letting them know that another user of
    the device, if compromised, could read their cached offline data.

  To expire the saved copy two hours after its last online capture:

      <FogOfWar.region max-age="PT2H">
        <h1>Trip details</h1>
      </FogOfWar.region>

  * ISO 8601 is supported, from Elixir's `Duration` module, like: `PT2H` (two hours), `P7D` (seven days),
    `P1M` (one month), and `P1Y` (one year, counted as 365 days).
  * Omit `max-age` to keep snapshots without a time limit. Offline visits do
    not renew the expiry. Bundled snapshots age from the time of export, so
    it is probably important that the bottom of your nav tree not have expiry.
    `Duration` uses 30-day months and 365-day years, and rounds up
    fractional milliseconds, so don't use this for anything you need to expire
    at a very precise date/time.

  ## Hook configuration

  If you don't want to use the component above, you could use the hook directly;
  the component renders a `section` with `phx-hook="FogOfWar"`. For a plain
  element, the hook and a stable DOM ID are enough:

      <main id="counter-page" phx-hook="FogOfWar">
        <output>{@count}</output>
      </main>

  The component passes `path`, `user-id`, and `require-user-id` to the hook
  as: `data-fog-of-war-path`, `data-fog-of-war-user-id`, and
  `data-fog-of-war-require-user-id="true"`. It passes the converted
  `max-age` as `data-fog-of-war-max-age-ms`.

  Note about path: FoW normally uses the committed browser pathname.
  The default is to leave `path` unset for a LiveView that can appear at multiple URLs.
  An override always saves under the specified path.
  Inferred capture skips URLs with query strings,
  and offline lookup matches same-origin URLs without query strings.

  """
  attr(:id, :string,
    default: "fog-of-war-region",
    doc: "Override the default DOM ID if needed to avoid a collision."
  )

  attr(:path, :string,
    default: nil,
    doc: "Override the cache route with a same-origin pathname such as /settings."
  )

  attr(:user_id, :any,
    default: nil,
    doc: "Stable, server-assigned account identifier. Omit for public capture."
  )

  attr(:require_user_id, :boolean,
    default: false,
    doc: "Skip capture when the account ID is missing or blank."
  )

  attr(:max_age, :any,
    default: nil,
    doc:
      "A positive ISO 8601 duration string, Duration struct, or integer milliseconds. Omit for no expiry."
  )

  attr(:class, :string, default: nil, doc: "CSS classes for the rendered section.")
  attr(:rest, :global, doc: "Additional HTML attributes for the section.")
  slot(:inner_block, required: true, doc: "The routed content to save and restore.")

  def region(assigns) do
    assigns = assign(assigns, :max_age_ms, max_age_ms!(assigns.max_age))

    ~H"""
    <section id={@id} phx-hook="FogOfWar" data-fog-of-war-max-age-ms={@max_age_ms} data-fog-of-war-path={@path} data-fog-of-war-user-id={@user_id} data-fog-of-war-require-user-id={if @require_user_id, do: "true"} class={@class} {@rest}>
      {render_slot(@inner_block)}
    </section>
    """
  end

  defp max_age_ms!(nil), do: nil

  defp max_age_ms!(value) when is_binary(value) do
    case Duration.from_iso8601(value) do
      {:ok, duration} -> max_age_ms!(duration)
      {:error, _} -> raise ArgumentError, "max-age must be an ISO 8601 duration, such as PT2H"
    end
  end

  defp max_age_ms!(%Duration{} = duration) do
    days = duration.year * 365 + duration.month * 30 + duration.week * 7 + duration.day
    seconds = ((days * 24 + duration.hour) * 60 + duration.minute) * 60 + duration.second
    microseconds = seconds * 1_000_000 + elem(duration.microsecond, 0)

    max_age_ms!(if microseconds > 0, do: div(microseconds + 999, 1000), else: 0)
  end

  defp max_age_ms!(milliseconds)
       when is_integer(milliseconds) and milliseconds > 0 and
              milliseconds <= 8_000_000_000_000_000,
       do: milliseconds

  defp max_age_ms!(_),
    do:
      raise(
        ArgumentError,
        "max-age must be a positive ISO 8601 duration, Duration struct, or integer milliseconds"
      )

  @doc """
  Opens a floating panel for inspecting saved pages and testing offline navigation.

  Put the panel outside the cached region, for example in a shared LiveView layout:

      <FogOfWar.dev_tools socket={@socket} enabled={true} dock="bottom-right" />

  To enable it across your app in development, omit `enabled` from the
  component call and add this to `config/config.exs`:

      config :fow, dev_tools: config_env() == :dev

  The panel is disabled by default. Call `installFogOfWar(liveSocket)`
  before connecting LiveSocket to register its hook.

  Use Pause to disconnect and Play to reconnect on the current route. In
  **Cache**, select a saved page to inspect its HTML or select a navigation
  event to see its outcome. The navigation log lasts until the document reloads.

  **Clear unused** removes saved pages whose routes are closed in cooperating
  FoW tabs. It requires browser support for Web Locks.
  """
  attr(:socket, :any, required: true, doc: "The current LiveView socket.")

  attr(:enabled, :boolean,
    default: nil,
    doc: "Show or hide the panel explicitly. Omit to use application configuration."
  )

  attr(:dock, :string,
    default: "bottom",
    values: ~w(top-left top top-right bottom-right bottom bottom-left),
    doc: "Initial dock; a saved user layout takes precedence"
  )

  attr(:semi_transparent, :boolean,
    default: false,
    doc: "Start with a translucent panel. The toolbar toggle lets the user change it."
  )

  attr(:scale, :any,
    default: 1.0,
    doc: "Positive numeric scale for text, controls, and spacing. The panel keeps its dimensions."
  )

  def dev_tools(assigns) do
    assigns =
      assign(
        assigns,
        :show,
        assigns.enabled ||
          (is_nil(assigns.enabled) && Application.get_env(:fow, :dev_tools, false))
      )

    ~H"""
    <%= if @show do %>
      {Phoenix.Component.live_render(@socket, FogOfWar.DevToolsLive,
        id: "fog-of-war-dev-tools", sticky: true,
        session: %{"dock" => @dock, "semi_transparent" => @semi_transparent, "scale" => @scale})}
    <% end %>
    """
  end

  @doc "Directory containing the package's JavaScript entry and supporting modules."
  def assets_path, do: Application.app_dir(:fow, "priv/static/js")
end

defmodule FoW do
  @moduledoc "Short module alias for `FogOfWar`."
  defdelegate region(assigns), to: FogOfWar
  defdelegate assets_path(), to: FogOfWar
  defdelegate dev_tools(assigns), to: FogOfWar
end
