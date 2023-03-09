defmodule WorkflowEx.Fields do
  @moduledoc """
  Defines an embedded schema for use in Workflow state containers. Note that it is expected to be mounted like this:

  ```
  typed_embedded_schema do
    embeds_one :__flow__, WorkflowEx.Fields
    # other fields for the workflow
  end
  ```
  """
  use TypedEctoSchema
  import Ecto.Changeset

  defguard is_flow_state(input) when is_map(input) and is_map_key(input, :__flow__)

  @primary_key false
  typed_embedded_schema do
    field(:flow_direction, WorkflowEx.Atom, default: :up)
    field(:flow_error_reason, WorkflowEx.Atom, default: :normal)

    # look for where step/observer might no longer be needed. Maybe just the MFA of what was just run is sufficient.
    field(:lifecycle_src, WorkflowEx.Atom)
    field(:last_result, WorkflowEx.Atom, default: :ok)

    # router sets these, and it's continue param determines the observer
    field(:step_index, :integer, default: 0)
    field(:step_func, WorkflowEx.Atom, default: :run)
  end

  def changeset(changeset, params) do
    cast(
      changeset,
      params,
      ~w[flow_direction flow_error_reason step_index step_func lifecycle_src last_result]a
    )
  end

  def merge(state, dest) when is_flow_state(state) do
    updated_flow =
      changeset(state.__flow__, dest)
      |> apply_action!(:update)

    %{state | __flow__: updated_flow}
  end

  def take(state, fields), do: Map.take(state.__flow__, fields)
  def get(state, field), do: Map.get(state.__flow__, field)
end
