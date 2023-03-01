defmodule WorkflowEx.Pid do
  @moduledoc """
  Allow "atom" as a field type for embedded_schema

  https://hexdocs.pm/ecto/Ecto.Schema.html#module-custom-types
  """
  use Ecto.Type

  @type t :: :pid

  def type, do: :string
  def cast(value), do: {:ok, value}
  def load(value), do: {:ok, value}
  def dump(value), do: {:ok, value}
end
