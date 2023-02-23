defmodule ExVisiflow.Fields do
  defmacro __using__(_) do
    quote location: :keep do
      import ExVisiflow.Fields
      import Ecto.Changeset
    end
  end

  @type t :: %{step: atom(), step_result: atom()}

  defmacro visiflow_fields(_opts \\ []) do
    quote location: :keep do
      field(:step_index, :integer, default: 0)
      field(:step_direction, :integer, default: 1)
      field(:func, ExVisiflow.Atom, default: :run)
      field(:step_result, ExVisiflow.Atom, default: nil)
      # field(:workflow_error, ExVisiflow.Atom, default: nil)
      # field(:step_wrapper, ExVisiflow.Atom, default: nil)
    end
  end
end
