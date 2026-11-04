defmodule CountersMobile.FrontierScreen do
  @moduledoc "Seamless Frontier native test screen; no wrapper controls."
  use Mob.Screen

  def mount(_, _, socket) do
    bundle = Application.app_dir(:counters_mobile, "priv/frontier") |> MobWebView.Bundle.load!()

    {:ok,
     Mob.Socket.assign(socket,
       bundle: bundle,
       url: bundle["url"],
       allow: [URI.to_string(%{URI.parse(bundle["url"]) | path: "/"})],
       events: []
     )}
  end

  def render(assigns) do
    ~MOB"""
    <Column fill_width={true} fill_height={true}>
      {MobWebView.view(id: :frontier, url: @url, bundle: @bundle, allow: @allow, fill_width: true, fill_height: true)}
    </Column>
    """
  end

  def handle_info({:qa_eval, caller, ref, code}, socket) do
    result = MobWebView.eval_js(:frontier, code)
    send(caller, {:qa_eval, ref, result})
    {:noreply, socket}
  end

  def handle_info({:mob_webview, :frontier, event, payload}, socket) do
    {:noreply,
     Mob.Socket.assign(
       socket,
       :events,
       Enum.take([{event, payload} | socket.assigns.events], 100)
     )}
  end

  def handle_info(_, socket), do: {:noreply, socket}
end
