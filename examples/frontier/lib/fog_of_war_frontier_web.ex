defmodule FogOfWarFrontierWeb do
  def static_paths, do: ~w(assets css images favicon.ico robots.txt)

  def live_view do
    quote do
      use Phoenix.LiveView
      import Phoenix.Component
      alias FogOfWarFrontierWeb.Layouts
    end
  end

  def html do
    quote do
      use Phoenix.Component
      import Phoenix.Controller, only: [get_csrf_token: 0]
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]
    end
  end

  defmacro __using__(which), do: apply(__MODULE__, which, [])
end
