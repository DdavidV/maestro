defmodule MaestroWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MaestroWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :workspace, :any,
    default: nil,
    doc: "the current `Maestro.Workspaces.Workspace.t()`, if any page is workspace-scoped"

  attr :active, :atom,
    default: nil,
    values: [nil, :overview, :run, :history, :workspaces],
    doc: "which primary sidebar entry to highlight as the current section"

  slot :inner_block, required: true

  slot :drawer,
    doc: "the workspace drawer, rendered in the sidebar's Explorer section when present"

  slot :breadcrumbs,
    doc: "an optional breadcrumb trail (e.g. <.breadcrumbs .../>), shown in the top bar"

  def app(assigns) do
    ~H"""
    <div class="flex h-full">
      <div
        id="app-sidebar-backdrop"
        class="fixed inset-0 z-30 hidden bg-black/40 lg:hidden"
        phx-click={toggle_sidebar()}
      />

      <aside
        id="app-sidebar"
        class="fixed inset-y-0 left-0 z-40 flex w-64 shrink-0 flex-col border-r border-base-300 bg-base-100 max-lg:hidden lg:static"
      >
        <div class="flex h-14 shrink-0 items-center justify-between border-b border-base-300 px-4">
          <.link navigate="/workspaces" class="flex items-center gap-2.5">
            <img src={~p"/images/logo.svg"} class="size-7" alt="" />
            <span class="text-[0.9375rem] font-semibold tracking-tight">Maestro</span>
          </.link>
          <button
            type="button"
            class="btn btn-ghost btn-sm btn-square lg:hidden"
            phx-click={toggle_sidebar()}
            aria-label="Close navigation"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <div :if={@workspace} class="px-3 pt-3">
          <.link
            navigate="/workspaces"
            title="Switch workspace"
            class="group flex items-center gap-2.5 rounded-field border border-base-300 px-2.5 py-2 transition-colors hover:bg-base-200"
          >
            <span class="grid size-7 shrink-0 place-items-center rounded-md bg-primary/10 text-xs font-semibold text-primary">
              {initials(@workspace.name)}
            </span>
            <span class="min-w-0 flex-1 leading-tight">
              <span class="block text-[0.6875rem] text-base-content/50">Workspace</span>
              <span class="block truncate text-sm font-medium">{@workspace.name}</span>
            </span>
            <.icon
              name="hero-chevron-up-down-mini"
              class="size-4 shrink-0 text-base-content/40 group-hover:text-base-content/70"
            />
          </.link>
        </div>

        <nav aria-label="Primary" class="space-y-0.5 px-3 pt-3">
          <.nav_link
            :if={@workspace}
            navigate={"/workspace/#{@workspace.id}"}
            icon="hero-squares-2x2"
            active={@active == :overview}
          >
            Overview
          </.nav_link>
          <.nav_link
            :if={@workspace}
            navigate={"/workspace/#{@workspace.id}/run"}
            icon="hero-play"
            active={@active == :run}
          >
            Run
          </.nav_link>
          <.nav_link
            :if={@workspace}
            navigate={"/workspace/#{@workspace.id}/history"}
            icon="hero-clock"
            active={@active == :history}
          >
            History
          </.nav_link>
          <.nav_link
            :if={!@workspace}
            navigate="/workspaces"
            icon="hero-rectangle-stack"
            active={@active == :workspaces}
          >
            Workspaces
          </.nav_link>
        </nav>

        <div :if={@drawer != []} class="mt-5 flex min-h-0 flex-1 flex-col">
          <div class="section-label px-5 pb-1.5">Explorer</div>
          <div class="min-h-0 flex-1 overflow-y-auto px-3 pb-3">
            {render_slot(@drawer)}
          </div>
        </div>
        <div :if={@drawer == []} class="flex-1" />

        <div class="flex shrink-0 items-center justify-between gap-2 border-t border-base-300 px-3 py-2.5">
          <a
            href="/api/docs"
            target="_blank"
            rel="noopener"
            class="nav-item px-2 py-1 text-xs"
            title="REST API documentation"
          >
            <.icon name="hero-code-bracket-square" class="size-4" /> API docs
          </a>
          <.theme_toggle />
        </div>
      </aside>

      <div class="flex min-w-0 flex-1 flex-col">
        <header class="flex h-14 shrink-0 items-center gap-3 border-b border-base-300 bg-base-100 px-4 sm:px-6 lg:px-8">
          <button
            type="button"
            class="btn btn-ghost btn-sm btn-square -ml-1.5 lg:hidden"
            phx-click={toggle_sidebar()}
            aria-label="Open navigation"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
          <div class="min-w-0 flex-1">{render_slot(@breadcrumbs)}</div>
        </header>

        <main class="min-h-0 flex-1 overflow-y-auto">
          <div class="mx-auto max-w-6xl space-y-6 px-4 py-8 sm:px-6 lg:px-8">
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={["nav-item", @active && "nav-item-active"]}
      aria-current={@active && "page"}
    >
      <.icon
        name={@icon}
        class={["size-4 shrink-0", if(@active, do: "text-primary", else: "text-base-content/50")]}
      />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp toggle_sidebar(js \\ %JS{}) do
    js
    |> JS.toggle_class("max-lg:hidden", to: "#app-sidebar")
    |> JS.toggle_class("hidden", to: "#app-sidebar-backdrop")
  end

  defp initials(name) do
    name
    |> String.split(~r/[\s_\-]+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex items-center rounded-full border border-base-300 bg-base-200 p-0.5">
      <div class="absolute inset-y-0.5 left-0.5 w-7 rounded-full border border-base-300 bg-base-100 shadow-xs transition-[left] [[data-theme=light]_&]:left-[1.875rem] [[data-theme=dark]_&]:left-[3.625rem] [[data-theme-source=system]_&]:!left-0.5" />

      <button
        :for={
          {theme, icon} <- [
            {"system", "hero-computer-desktop-micro"},
            {"light", "hero-sun-micro"},
            {"dark", "hero-moon-micro"}
          ]
        }
        type="button"
        class="relative grid h-6 w-7 cursor-pointer place-items-center text-base-content/50 hover:text-base-content"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme={theme}
        title={"#{String.capitalize(theme)} theme"}
        aria-label={"#{String.capitalize(theme)} theme"}
      >
        <.icon name={icon} class="size-3.5" />
      </button>
    </div>
    """
  end
end
