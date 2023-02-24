defmodule ExVisiflow.Fields do
  use TypedEctoSchema
  import Ecto.Changeset

  typed_embedded_schema do
    field(:flow_direction, ExVisiflow.Atom, default: :up)
    field(:flow_error_reason, ExVisiflow.Atom, default: :normal)

    field(:step_index, :integer, default: 0)
    field(:step_mod, ExVisiflow.Atom, default: nil)
    field(:step_func, ExVisiflow.Atom, default: :run)
    field(:step_result, ExVisiflow.Atom, default: nil)

    field(:wrapper_mod, ExVisiflow.Atom, default: nil)
    field(:wrapper_func, ExVisiflow.Atom, default: nil)
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
