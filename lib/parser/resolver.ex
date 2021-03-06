defmodule Thrift.Parser.Resolver do
  @moduledoc """
  A resolver for references.
  During file parsing, all new generated thrift concepts flow through this resolver
  and are added to its global database of names. At the end, the database is dumped into
  the FileGroup so it can resolve references.
  """
  alias Thrift.Parser.ParsedFile

  def start_link do
    Agent.start_link(&Map.new/0, name: __MODULE__)
  end

  def stop do
    Agent.stop(__MODULE__)
  end

  def add(%ParsedFile{} = f) do
    Agent.update(__MODULE__, fn(state) ->
      state
      |> update(f.name, f.schema.services)
      |> update(f.name, f.schema.structs)
      |> update(f.name, f.schema.exceptions)
      |> update(f.name, f.schema.unions)
      |> update(f.name, f.schema.enums)
    end)
  end

  def get do
    Agent.get(__MODULE__, &(&1))
  end

  defp update(%{} = state, include_name, %{} = local_mappings) do
    new_mappings = local_mappings
    |> Map.new(fn {name, val} ->
      {:"#{include_name}.#{name}", Map.put(val, :name, :"#{include_name}.#{name}")}
    end)

    Map.merge(state, new_mappings)
  end
end
