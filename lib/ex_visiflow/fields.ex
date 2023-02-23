defmodule ExVisiflow.Fields do
  defmacro __using__(_) do
    quote location: :keep do
      import ExVisiflow.Fields
      import Ecto.Changeset
    end
  end

  @type t :: %{step: atom(), step_result: atom(), step_wrapper: atom()}

  defmacro visiflow_fields(_opts \\ []) do
    quote location: :keep do
      field(:step_index, :integer)
      field(:did_rollback, :boolean)
      field(:step_result, ExVisiflow.Atom)
      field(:workflow_error, ExVisiflow.Atom)
      field(:step_wrapper, ExVisiflow.Atom)
    end
  end
end
