defmodule Helmscout.ManifestTest do
  use ExUnit.Case, async: true

  alias Helmscout.Manifest

  test "read_all handles multiple documents" do
    yaml = """
    kind: A
    ---
    kind: B
    """

    assert {:ok, [%{"kind" => "A"}, %{"kind" => "B"}]} = Manifest.read_all(yaml)
  end

  test "read_all returns an error for malformed yaml" do
    assert {:error, _} = Manifest.read_all("foo: [unclosed\n  bar: :::")
  end

  test "get traverses maps and is nil-safe" do
    doc = %{"a" => %{"b" => %{"c" => 1}}}

    assert Manifest.get(doc, "a.b.c") == 1
    assert Manifest.get(doc, "a.b.missing") == nil
    assert Manifest.get(doc, "a.x.y.z") == nil
    assert Manifest.get(doc, "nope") == nil
  end

  test "get supports escaped dots in keys" do
    doc = %{"metadata" => %{"annotations" => %{"hajimari.io/icon" => "plex"}}}

    assert Manifest.get(doc, "metadata.annotations.hajimari\\.io/icon") == "plex"
  end

  test "matches? applies a predicate" do
    doc = %{"apiVersion" => "helm.toolkit.fluxcd.io/v2"}

    assert Manifest.matches?(doc, "apiVersion", &String.starts_with?(&1, "helm.toolkit"))
    refute Manifest.matches?(doc, "apiVersion", &String.starts_with?(&1, "argoproj"))
    refute Manifest.matches?(doc, "missing")
  end
end
