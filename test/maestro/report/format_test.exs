defmodule Maestro.Report.FormatTest do
  use ExUnit.Case, async: false

  alias Maestro.Report.DefaultLayout
  alias Maestro.Report.Format
  alias Maestro.Report.JUnit

  defmodule PlainLayout do
    @moduledoc false
    @behaviour Maestro.Report.Format

    @impl true
    def render(_model), do: "plain"
  end

  defmodule CsvFormat do
    @moduledoc false
    @behaviour Maestro.Report.Format

    @impl true
    def render(_model), do: "a,b"

    @impl true
    def extension, do: "csv"

    @impl true
    def content_type, do: "text/csv"
  end

  setup do
    on_exit(fn ->
      Application.delete_env(:maestro, :report_formats)
    end)
  end

  test "the built-in formats describe themselves" do
    assert {Format.name(DefaultLayout), Format.extension(DefaultLayout)} == {"html", "html"}
    assert {Format.name(JUnit), Format.extension(JUnit)} == {"junit", "xml"}
  end

  test "a module with only render/1 gets HTML defaults" do
    assert Format.name(PlainLayout) == "html"
    assert Format.extension(PlainLayout) == "html"
    assert Format.content_type(PlainLayout) == "text/html"
  end

  test "name defaults to the extension when only extension is given" do
    assert Format.name(CsvFormat) == "csv"
    assert Format.content_type(CsvFormat) == "text/csv"
  end

  test "configured/0 defaults to just the built-in HTML report" do
    assert Format.configured() == [DefaultLayout]
  end

  test "configured/0 reads :report_formats when set" do
    Application.put_env(:maestro, :report_formats, [DefaultLayout, JUnit])
    assert Format.configured() == [DefaultLayout, JUnit]
  end

  test "built-in formats can be found even when not configured" do
    assert Format.find("junit") == {:ok, JUnit}
    assert Format.find("html") == {:ok, DefaultLayout}
    assert Format.find("nope") == {:error, :unknown_format}
  end

  test "a configured format shadows a built-in with the same name" do
    Application.put_env(:maestro, :report_formats, [PlainLayout])

    assert Format.find("html") == {:ok, PlainLayout}
    refute DefaultLayout in Format.available()
  end

  test "custom configured formats are findable by name" do
    Application.put_env(:maestro, :report_formats, [DefaultLayout, CsvFormat])
    assert Format.find("csv") == {:ok, CsvFormat}
  end
end
