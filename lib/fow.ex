defmodule FogOfWar do
  @moduledoc """
  Adds read-only offline navigation to Phoenix LiveView pages.
  Use via `FogOfWar.region/1`.

  # Usage

  For a simple public page, where everyone will see the same data,
  wrap the routed content in a region.

      <FogOfWar.region>
        <.link navigate={~p"/"}>Back to index</.link>
        <output>{@detail}</output>
      </FogOfWar.region>

  Each time they visit that route, it's cached in the browser.

  ## Caching user-specific markup
  **What about multiple users?** If Bob and Sally
  used the same open browser, they shouldn't
  see each other's cached content!

  Use `user_id` to save personalized markup:

      <FogOfWar.region
        user_id={@current_user && @current_user.id}
        require_user_id
      >
        <h1>Settings</h1>
        <p>{@current_user && @current_user.email}</p>
      </FogOfWar.region>

  With cached content in IndexDB encrypted at rest, to
  prevent low-effort dumping attacks
  on compromised systems. And when using user-id on a region,
  users can't see markup cached from other users who may have
  logged in on the same device.

  However, it is only encrypted with a key that is stored locally.
  So it is possible that if Bob signs in with the same browser Sally
  has used, and Bob is either malicious or compromised by something
  that can execute scripts in his browser and knows about FogOfWar,
  Sally's data can be exposed.

  The solution is to ensure that when Sally logs out, her key is
  no longer available. Let's set this up.

  ## Cache security

  To give user-specific markup much stronger security guarantees,
  you need to take another step.

  To protect private snapshots after logout, enable server-derived account
  keys. Configure a callback that receives the authenticated connection and
  returns the same stable string as the region's `user_id`, or `nil` to deny
  access. Include the tenant when account IDs are tenant-local.

      config :fow, account_key_identity: {MyAppWeb.OfflineIdentity, :account_scope}

  For example, if your authentication plug assigns `current_user`:

      defmodule MyAppWeb.OfflineIdentity do
        def account_scope(%Plug.Conn{assigns: %{current_user: %{id: id}}}), do: to_string(id)
        def account_scope(_conn), do: nil
      end

  Add the built-in endpoint inside your authenticated, CSRF-protected browser
  scope. Keep this path at the application root.

      post "/_fow/account-key", FogOfWar.AccountKeyEndpoint, []

  FoW reuses the matching key in IndexedDB. If it is missing or belongs to
  another account, FoW requests a key the first time a signed-in region renders.

  ### Locking the cache on logout

  There are two ways to lock the per-user cache: in the UI when the users click
  a logout button of some sort, or programmatically from the server, from
  any connected LiveView.

  The preferred approach is in the UI, because there's no chance for eg.
  a redirect to accidentally outrun the clearing action.

  **In the UI**: Wrap your existing logout control with `logout/1`. FoW clears the stored
  account key before forwarding the click or form submission. Phoenix still
  handles the session and any cross-tab refreshes.

      <FogOfWar.logout>
        <.link href={~p"/users/log-out"} method="delete">Log out</.link>
      </FogOfWar.logout>

  **From a LiveView**: a LiveView can also request the same local clear with
  `push_event(socket, "fow:logout", %{})`. FoW listens even when the page has no
  region active, so this can be done from any LiveView.
  Let the browser finish the clear before redirecting. If you need
  completion, listen for the browser event `fog-of-war:account-locked`.
  See the [upgrade and logout notes](readme.html#optional-account-keys).

  ## Cache expiry
  To expire the saved copy two hours after its last online capture:

      <FogOfWar.region max_age="PT2H">
        <h1>Trip details</h1>
      </FogOfWar.region>

  * ISO 8601 is supported, from Elixir's `Duration` module, like: `PT2H` (two hours), `P7D` (seven days),
    `P1M` (one month), and `P1Y` (one year, counted as 365 days).
  * Omit `max_age` to keep snapshots without a time limit. Offline visits do
    not renew the expiry. Bundled snapshots age from the time of export, so
    it is probably important that the bottom of your nav tree not have expiry.
    `Duration` uses 30-day months and 365-day years, and rounds up
    fractional milliseconds, so don't use this for anything you need to expire
    at a very precise date/time.
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

  For account scoping and logout setup, use the following pattern,
  but also see this module's docs on cache security!

      <FogOfWar.region
        user_id={@current_user && @current_user.id}
        require_user_id
      >
        <h1>Settings</h1>
        <p>{@current_user && @current_user.email}</p>
      </FogOfWar.region>

  To expire the saved copy two hours after its last online capture:

      <FogOfWar.region max_age="PT2H">
        <h1>Trip details</h1>
      </FogOfWar.region>

  * ISO 8601 is supported, from Elixir's `Duration` module, like: `PT2H` (two hours), `P7D` (seven days),
    `P1M` (one month), and `P1Y` (one year, counted as 365 days).
  * Omit `max_age` to keep snapshots without a time limit. Offline visits do
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

  The component passes `path`, `user_id`, and `require_user_id` to the hook
  as: `data-fog-of-war-path`, `data-fog-of-war-user-id`, and
  `data-fog-of-war-require-user-id="true"`. It passes the converted
  `max_age` as `data-fog-of-war-max-age-ms`.

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
    doc: "A positive ISO 8601 duration string, Duration struct, or integer milliseconds. Omit for no expiry."
  )

  attr(:class, :string, default: nil, doc: "CSS classes for the rendered section.")
  attr(:rest, :global, doc: "Additional HTML attributes for the section.")
  slot(:inner_block, required: true, doc: "The routed content to save and restore.")

  def region(assigns) do
    assigns = assign(assigns, :max_age_ms, max_age_ms!(assigns.max_age))

    ~H"""
    <section id={@id} phx-hook="FogOfWar" data-fog-of-war-account-keys={if Application.get_env(:fow, :account_key_identity), do: "true"} data-fog-of-war-max-age-ms={@max_age_ms} data-fog-of-war-path={@path} data-fog-of-war-user-id={@user_id} data-fog-of-war-require-user-id={if @require_user_id, do: "true"} class={@class} {@rest}>
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
       when is_integer(milliseconds) and milliseconds > 0 and milliseconds <= 8_000_000_000_000_000, do: milliseconds

  defp max_age_ms!(_),
    do: raise(ArgumentError, "max-age must be a positive ISO 8601 duration, Duration struct, or integer milliseconds")

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

  @doc """
  Clears the offline account key before activating the enclosed logout control.

  Wrap only the logout link, button, or dedicated logout form. Use an ordinary
  same-tab link, a native button with `phx-click`, or a form. To cover keyboard
  form submission, wrap the whole form. FoW forwards the original control
  after clearing the key so the application's existing logout handler runs.
  Place the wrapper outside any region that can be rendered offline.

  Use a distinct `id` for each wrapper if the page has more than one.
  """
  attr(:id, :string, default: "fog-of-war-logout")
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def logout(assigns) do
    ~H"""
    <div id={@id} phx-hook="FogOfWarLogout" {@rest}>
      {render_slot(@inner_block)}
      <span data-fow-logout-status role="alert"></span>
    </div>
    """
  end

  @doc "Directory containing the package's JavaScript entry and supporting modules."
  def assets_path, do: Application.app_dir(:fow, "priv/static/js")
end

defmodule FoW do
  @moduledoc "Short module alias for `FogOfWar`."
  defdelegate region(assigns), to: FogOfWar
  defdelegate logout(assigns), to: FogOfWar
  defdelegate assets_path(), to: FogOfWar
  defdelegate dev_tools(assigns), to: FogOfWar
end
