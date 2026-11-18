defmodule FogOfWar.DevToolsLive do
  @moduledoc false
  use Phoenix.LiveView

  @css_path Path.expand("../../priv/static/css/dev-tools.css", __DIR__)
  @external_resource @css_path
  @css File.read!(@css_path)

  def mount(_params, session, socket) do
    scale = Map.get(session, "scale", 1.0)
    if !(is_number(scale) and scale > 0), do: raise(ArgumentError, "DevTools scale must be a positive number")

    {:ok,
     assign(socket,
       dock: Map.get(session, "dock", "bottom"),
       css: @css,
       semi_transparent: Map.get(session, "semi_transparent", false),
       scale: scale
     ), layout: false}
  end

  def render(assigns) do
    ~H"""
    <aside id="fog-of-war-dev-tools-panel" phx-hook="FogOfWarDevTools"
      style={"--fog-of-war-dev-tools-scale: #{@scale};"}
      data-fog-of-war-dev-tools data-default-dock={@dock} data-semi-transparent={to_string(@semi_transparent)} phx-update="ignore">
      <template>
        <style><%= Phoenix.HTML.raw(@css) %></style>
        <section class="tools" aria-label="Fog of War developer tools">
          <button class="launcher" type="button" data-action="expand" aria-expanded="false">
            <i class="dot" aria-hidden="true"></i>Fog of War<span>+</span>
          </button>
          <div class="panel" hidden>
            <header>
              <button class="drag-handle" type="button" data-drag aria-label="Move developer tools" title="Drag to a corner or the top/bottom center; arrow keys change dock">⠿ <strong>Fog of War</strong></button>
              <div role="tablist" aria-label="Developer tools">
                <button type="button" role="tab" id="cache-tab" aria-controls="cache-pane"
                  aria-selected="true" data-tab="cache">Cache <span data-count>0</span></button>
                <button type="button" role="tab" id="help-tab" aria-controls="help-pane"
                  aria-selected="false" tabindex="-1" data-tab="help">What's This?</button>
              </div>
              <button class="transparency-toggle" type="button" data-action="transparency" aria-label="Semi-transparent developer tools" aria-pressed="false" title="Toggle semi-transparent developer tools">
                <svg viewBox="0 0 16 16" aria-hidden="true"><rect x="2" y="2" width="9" height="9" rx="1" /><rect x="6" y="6" width="8" height="8" rx="1" /></svg>
              </button>
              <button class="connection-toggle" type="button" data-action="connection" aria-label="Disconnect socket" title="Disconnect socket">
                <svg viewBox="0 0 16 16" aria-hidden="true"><path class="pause-icon" d="M5 3v10M11 3v10" /><path class="play-icon" d="M5 3l8 5-8 5z" /></svg>
              </button>
              <span class="connection-status"><i class="dot" aria-hidden="true"></i><span data-state>Disconnected</span></span>
              <button type="button" class="collapse" data-action="collapse" aria-label="Collapse developer tools">−</button>
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

                <h1>Fog of War</h1>
                <h2>Declarative offline for LiveView</h2>

                <p style="zoom: 1.1;">
                  <a href="#liveview">LiveView is great.</a>
                  <a href="#offline">Offline is also great.</a>
                  <a href="#fow">Fog of War is an approach to fairly easy offline</a>
                  which can work for a wide variety of apps.
                </p>

                <h3 id="fow">Fog of War is offline support via simple caching</h3>

                <p>
                  Fog of War is an idiom from old Real-Time Strategy games.
                  Like an explored part of a game map, it shows what was there
                  the last time you looked! Specifically, if you're offline, it
                  shows the last markup that the LiveView for that screen loaded with.
                  Unvisited screens are still unavailable, but you can style links
                  to them gracefully. And, you can even create a bundle of important
                  screens to 'pre-explore' the map, which is useful for mobile, where
                  the first experience might be an offline one.
                </p>

                <h2 id="liveview">LiveView is Great</h2>
                <p>
                  LiveView is great. Most apps that do something
                  interesting are online, and have non-trivial server code.
                  And LiveView is the best way to make interesting apps.
                </p>

                <p>
                  But you used to be forced to split the program
                  up. For instance, when they pick a username, and you
                  automatically check to see if that name's
                  available as they're typing, you
                  need a separate little program, running in the browser.
                </p>

                <p>
                  Not a big deal at first, but you wouldn't believe
                  just how fragmented programs ended up.
                </p>

                <p>
                  Especially from about 2010-2020. Eventually, billion-dollar
                  startups were created whose sole reason to exist
                  was, basically, to paper this over that mess.
                </p>

                <p>
                  So, LiveView is great. No split brain, and you can drive any
                  complex client-side behavior you want from the server.
                </p>

                <h2 id="offline">Offline is great</h2>

                <p>
                  If you care about the user experience, and especially if you
                  want to wrap it in a mobile app, you need to think about offline behavior.
                  (There are those who will say that, if you care about
                  the user experience, you cannot possibly use web technologies
                  extensively in a mobile application. They are not usually saying it
                  because they believe it to be strictly true, but for other reasons).
                </p>

                <p>
                  If you install an app from an App Store, and then open it offline,
                  it is reasonable to expect that it shows a user a screen that is
                  ready to use, not a spinner. This is even true if that screen
                  requires you to sign in or sign up, and that
                  step will not work because you're offline.
                </p>

                <p>
                  Sure, some screens in an app require being online.
                  Showing a list of vacation rentals, for instance! But
                  much navigation should still be possible even when offline.
                  The creator of the app knows what screens make sense to
                  have cached and available for navigation locally, and which
                  ones need to be grayed out, or show some other graceful offline indication.
                </p>
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
