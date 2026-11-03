defmodule FogOfWar.DevToolsLive do
  @moduledoc false
  use Phoenix.LiveView

  @css_path Path.expand("../../priv/static/css/dev-tools.css", __DIR__)
  @external_resource @css_path
  @css File.read!(@css_path)

  def mount(_params, session, socket) do
    {:ok,
     assign(socket, css: @css, semi_transparent: Map.get(session, "semi_transparent", false)),
     layout: false}
  end

  def render(assigns) do
    ~H"""
    <aside id="fog-of-war-dev-tools-panel" phx-hook="FogOfWarDevTools"
      data-fog-of-war-dev-tools data-semi-transparent={to_string(@semi_transparent)} phx-update="ignore">
      <template>
        <style><%= Phoenix.HTML.raw(@css) %></style>
        <section class="tools" aria-label="Fog of War developer tools">
          <button class="launcher" type="button" data-action="expand" aria-expanded="false">
            <i class="dot" aria-hidden="true"></i>Fog of War<span>⌃</span>
          </button>
          <div class="panel" hidden>
            <header>
              <button class="drag-handle" type="button" data-drag aria-label="Move developer tools" title="Drag to a corner or the top/bottom center; arrow keys change dock">⠿ <strong>Fog of War</strong></button>
              <div role="tablist" aria-label="Developer tools">
                <button type="button" role="tab" id="cache-tab" aria-controls="cache-pane"
                  aria-selected="true" data-tab="cache">Cache <span data-count>0</span></button>
                <button type="button" role="tab" id="help-tab" aria-controls="help-pane"
                  aria-selected="false" tabindex="-1" data-tab="help">Help</button>
              </div>
              <button class="transparency-toggle" type="button" data-action="transparency" aria-label="Semi-transparent developer tools" aria-pressed="false" title="Toggle semi-transparent developer tools">
                <svg viewBox="0 0 16 16" aria-hidden="true"><rect x="2" y="2" width="9" height="9" rx="1" /><rect x="6" y="6" width="8" height="8" rx="1" /></svg>
              </button>
              <span class="connection-status"><i class="dot" aria-hidden="true"></i><span data-state>Disconnected</span></span>
              <button class="connection-toggle" type="button" data-action="connection" aria-label="Disconnect socket" title="Disconnect socket">
                <svg viewBox="0 0 16 16" aria-hidden="true"><path class="pause-icon" d="M5 3v10M11 3v10" /><path class="play-icon" d="M5 3l8 5-8 5z" /></svg>
              </button>
              <button type="button" class="collapse" data-action="collapse" aria-label="Collapse developer tools">⌄</button>
            </header>
            <section id="cache-pane" role="tabpanel" aria-labelledby="cache-tab">
              <div class="cache-bar">
                <label><input type="checkbox" data-filter="cache" checked />Cache</label>
                <label><input type="checkbox" data-filter="nav" checked />Nav</label>
                <span data-total></span>
                <button type="button" data-action="refresh">Refresh</button>
                <button type="button" data-action="clear">Clear unused</button>
                <button type="button" data-action="clear-nav" title="Clear this document's in-memory navigation log">Clear nav</button>
                <span class="message" data-cache-message role="status"></span>
              </div>
              <div class="explorer">
                <div class="entries"><table aria-label="Cache and navigation timeline">
                  <thead><tr>
                    <th><button data-sort="path">Path</button></th>
                    <th><button data-sort="kind">Event</button></th>
                    <th><button data-sort="bytes">Stored</button></th>
                    <th aria-sort="descending"><button data-sort="time">When ↓</button></th>
                    <th title="Snapshot record format, not package version. Compatibility tag is in the details."><button data-sort="version">Vsn</button></th>
                    <th><button data-sort="open">Open</button></th>
                  </tr></thead>
                  <tbody data-rows></tbody>
                </table><p class="empty" data-empty hidden>No matching records.</p></div>
                <div class="splitter" role="separator" aria-label="Resize cache list and details" aria-orientation="vertical" aria-valuemin="20" aria-valuemax="80" aria-valuenow="58" tabindex="0"></div>
                <pre data-detail aria-label="Cached page details">Select a saved page or navigation event.</pre>
              </div>
              <div class="status-line"><span data-message role="status"></span><span data-dock-label></span></div>
            </section>
            <section id="help-pane" role="tabpanel" aria-labelledby="help-tab" hidden>
              <div class="help-copy">
                <h2>A website that remembers what you saw</h2>
                <p>LiveView keeps the working app on the server. It sends the browser HTML, then small updates as things change. That is server-driven UI: one place describes the screen and handles its actions.</p>
                <p>Fog of War remembers the pages you choose. Lose contact with the server and you can still visit those remembered pages. Like an explored part of a game map, they show what was there the last time you looked. Unvisited places stay unavailable.</p>
                <h3>Why this fits LiveView</h3>
                <p>The server already produces the screen. We save that HTML rather than build a second offline version of the app or copy its database into the browser. Add one hook to a page’s top-level content; keep using LiveView online.</p>
                <h3>Remembered does not mean live</h3>
                <p>Saved values can be old. Server actions are blocked offline and are not queued. Reconnecting after browsing cached pages loads fresh server state at the route you chose. This is read-only memory, not offline editing or background synchronization.</p>
                <h3>Reading this tool</h3>
                <p><strong>Cache</strong> shows one stored page per route. <strong>Nav</strong> shows attempts, live arrivals, cached visits and denied destinations. Events stay in memory in this document (up to 200); they are never written to localStorage and disappear on a full reload. Newest records appear first. Click a column to change sorting.</p>
                <p><strong>Vsn</strong> is the snapshot record format, currently 1. The separate <code>build</code> value in details is a renderer compatibility tag, not the package version. Compression is a storage encoding, not another app version.</p>
                <p>Stored sizes estimate localStorage’s UTF-16 keys and values. Clear unused preserves routes open in Fog of War tabs; it requires Web Locks. Pick content appropriate to remember on this device, and handle account changes and logout in your app.</p>
                <p>Drag the header to dock at a corner or the top/bottom center. Corners use a compact, resizable panel; top and bottom centers span the window. Drag the divider to resize the list. The grip, divider and resize handle also accept arrow keys. Panel layout is remembered in sessionStorage, separately from the page cache.</p>
              </div>
            </section>
            <div class="resize-handle" role="separator" aria-label="Resize developer tools" tabindex="0"></div>
          </div>
        </section>
      </template>
    </aside>
    """
  end
end
