defmodule TestFields do
  use TypedEctoSchema
  use WorkflowEx.TypedSchemaHelpers

  typed_embedded_schema do
    embeds_one :__flow__, WorkflowEx.Fields
  end

  def_new(required: :none, default: [{:__flow__, %WorkflowEx.Fields{} |> Map.from_struct()}])
end

defmodule WorkflowEx.FieldsTest do
  use ExUnit.Case, async: true

  test "when including the visiflow_fields, defaults are provided" do
    assert {:ok,
            %TestFields{
              __flow__: %WorkflowEx.Fields{
                step_index: 0,
                flow_direction: :up,
                step_mod: nil,
                step_func: :run,
                step_result: nil,
                flow_error_reason: :normal,
                wrapper_mod: nil,
                wrapper_func: nil
              }
            }} == TestFields.new(%{})
  end
end
