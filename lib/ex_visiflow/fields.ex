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
      field(:flow_direction, ExVisiflow.Atom, default: :up)
      field(:step_mod, ExVisiflow.Atom, default: nil)
      field(:step_func, ExVisiflow.Atom, default: :run)
      field(:step_result, ExVisiflow.Atom, default: nil)
      field(:flow_error_reason, ExVisiflow.Atom, default: :normal)
      field(:wrapper_mod, ExVisiflow.Atom, default: nil)
      field(:wrapper_func, ExVisiflow.Atom, default: nil)
      field(:wrapper_result, ExVisiflow.Atom, default: nil)
    end
  end
end
