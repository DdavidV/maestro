import Config

config :maestro,
  host_app: :mini_bank,
  workspaces_registry_path: Path.expand("../priv/workspaces.json", __DIR__),
  report_dir: Path.expand("../priv/reports", __DIR__)
