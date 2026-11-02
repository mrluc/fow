defmodule FogOfWar.DevToolsLive do
  @moduledoc false
  use Phoenix.LiveView

  @css_path Path.expand("../../priv/static/css/dev-tools.css", __DIR__)
  @external_resource @css_path
  @css File.read!(@css_path)

  def mount(_params, _session, socket), do: {:ok, assign(socket, :css, @css), layout: false}

  def render(assigns) do
    ~H"""
    <aside id="fog-of-war-dev-tools-panel" phx-hook="FogOfWarDevTools"
      data-fog-of-war-dev-tools phx-update="ignore">
      <template>
        <style><%= Phoenix.HTML.raw(@css) %></style>
        <section class="tools" aria-label="Fog of War developer tools">
          <button class="launcher" type="button" data-action="expand" aria-expanded="false">
            <i class="dot" aria-hidden="true"></i>Fog of War<span>⌃</span>
          </button>
          <div class="panel" hidden>
            <header>
              <strong>Fog of War</strong>
              <div role="tablist" aria-label="Developer tools">
                <button type="button" role="tab" id="connection-tab" aria-controls="connection-pane"
                  aria-selected="true" data-tab="connection">Connection</button>
                <button type="button" role="tab" id="cache-tab" aria-controls="cache-pane"
                  aria-selected="false" tabindex="-1" data-tab="cache">Cache <span data-count>0</span></button>
              </div>
              <span class="summary" data-summary></span>
              <button type="button" data-action="collapse" aria-label="Collapse developer tools">⌄</button>
            </header>
            <section id="connection-pane" role="tabpanel" aria-labelledby="connection-tab" class="connection">
              <span class="state" data-state>Connecting</span>
              <button type="button" data-action="connection">Pause connection</button>
              <span class="message" data-message role="status" title=""></span>
            </section>
            <section id="cache-pane" role="tabpanel" aria-labelledby="cache-tab" hidden>
              <div class="cache-bar">
                <span data-total></span>
                <button type="button" data-action="refresh">Refresh</button>
                <button type="button" data-action="clear">Clear unused</button>
                <span class="message" data-cache-message role="status"></span>
              </div>
              <div class="explorer">
                <div class="entries"><table aria-label="Cached pages">
                  <thead><tr><th>Path ↑</th><th>Stored</th><th>Saved</th><th>Build</th><th>Open</th></tr></thead>
                  <tbody data-rows></tbody>
                </table><p class="empty" data-empty hidden>No saved pages.</p></div>
                <pre data-detail aria-label="Cached page details">Select a page to inspect its metadata and HTML.</pre>
              </div>
            </section>
          </div>
        </section>
      </template>
    </aside>
    """
  end
end
