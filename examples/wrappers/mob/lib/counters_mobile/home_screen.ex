defmodule CountersMobile.HomeScreen do
  use Mob.Screen
  @live "http://127.0.0.1:47180/"
  def mount(_, _, socket) do
    local = CountersMobile.PublicShell.url()

    {:ok,
     Mob.Socket.assign(socket,
       url: local,
       local: local,
       allowed: [URI.to_string(%{URI.parse(local) | path: "/"}), "http://127.0.0.1:47180/"]
     )}
  end

  def render(assigns) do
    ~MOB"""
    <Column fill_width={true} fill_height={true}>
      <Row padding={6} gap={8}>
        <Text text={"Counters"} weight={1} />
        <Button text="Live" on_tap={{self(), :live}} />
        <Button text="Offline" on_tap={{self(), :offline}} />
      </Row>
      {MobWebView.view(id: :site, url: @url, allow: @allowed, weight: 1, fill_width: true, fill_height: true)}
    </Column>
    """
  end

  def handle_info({:tap, :live}, socket), do: {:noreply, navigate(socket, @live)}

  def handle_info({:tap, :offline}, socket),
    do: {:noreply, navigate(socket, socket.assigns.local)}

  def handle_info(_, socket), do: {:noreply, socket}
  defp navigate(socket, url), do: Mob.Socket.assign(socket, :url, url)
end
