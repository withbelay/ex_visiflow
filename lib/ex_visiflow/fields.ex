defmodule WorkflowEx.Fields do
  @moduledoc """
  Defines an embedded schema for use in Workflow state containers. Note that it is expected to be mounted like this:

  ```
  typed_embedded_schema do
    embeds_one :__visi__, WorkflowEx.Fields
    # other fields for the workflow
  end
  ```
  """
  use TypedEctoSchema
  import Ecto.Changeset

  typed_embedded_schema do
    field(:flow_direction, WorkflowEx.Atom, default: :up)
    field(:flow_error_reason, WorkflowEx.Atom, default: :normal)

    field(:step_index, :integer, default: 0)
    field(:step_mod, WorkflowEx.Atom, default: nil)
    field(:step_func, WorkflowEx.Atom, default: :run)
    field(:step_result, WorkflowEx.Atom, default: nil)

    field(:wrapper_mod, WorkflowEx.Atom, default: nil)
    field(:wrapper_func, WorkflowEx.Atom, default: nil)
  end

  def changeset(changeset, params) do
    params = Map.merge(%{step_index: 0, flow_error_reason: :normal, flow_direction: :up}, params)

    cast(
      changeset,
      params,
      ~w[flow_direction flow_error_reason step_index step_mod step_func step_result wrapper_mod wrapper_func]a
    )
  end
end
