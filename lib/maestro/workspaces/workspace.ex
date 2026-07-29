defmodule Maestro.Workspaces.Workspace do
  @moduledoc """
  A self-contained collection of resources: its own `suites`/`scenarios`/
  `datasets`/`templates`/`test_plans` subdirectories under `root_dir`, with
  no references crossing into any other workspace's directory (enforced by
  `Maestro.Resources.Resolver`, not just convention here).

  `id` is a URL-safe slug, generated once at creation and never changed
  after multiple pages/processes reference it (LiveView routes, PubSub
  topics for runs against this workspace) it must stay stable for the
  workspace's whole lifetime. `name` is a cosmetic, editable display label,
  same distinction `Maestro.suite/0`'s own `id`/`name` already draws.
  """

  @type vcs :: :none | :git

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          root_dir: String.t(),
          created_at: DateTime.t(),
          vcs: vcs
        }

  @enforce_keys [:id, :name, :root_dir, :created_at]
  defstruct [:id, :name, :root_dir, :created_at, vcs: :none]
end
