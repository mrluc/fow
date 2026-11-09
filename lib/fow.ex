defmodule FogOfWar do
  @moduledoc """
  Page-level rendered snapshots for LiveView. Put the `FogOfWar` hook on the
  top-level routed content, or use `FogOfWar.region/1` as that top-level element.
  Offline navigation restores only that element; surrounding content is not saved.
  The application chooses its browser-local caching and account policy.
  """
  use Phoenix.Component

  attr(:id, :string, required: true)
  attr(:path, :string, required: true)
  attr(:class, :string, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def region(assigns) do
    ~H"""
    <section id={@id} phx-hook="FogOfWar" data-fog-of-war-path={@path} class={@class} {@rest}>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc "Mounts the package's sticky developer tools. The `enabled={true | false}` attribute overrides `config :fow, dev_tools: true`; omit it to use configuration. This can be an application authorization expression."
  attr(:socket, :any, required: true)
  attr(:enabled, :boolean, default: nil)

  attr(:dock, :string, default: "bottom",
    values: ~w(top-left top top-right bottom-right bottom bottom-left),
    doc: "Initial dock; a saved user layout takes precedence")

  attr(:semi_transparent, :boolean, default: false)

  attr(:scale, :any,
    default: 1.0,
    doc: "Positive numeric scale for developer-tool text and controls"
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
