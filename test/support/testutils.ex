defmodule Maestro.TestUtils do

  def write_resource!(dir \\ Maestro.Resources.resource_dir(), kind_subdir, rel_path, content) do
    file = Path.join([dir, kind_subdir, rel_path <> ".json"])
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, Jason.encode!(content))
  end

end
