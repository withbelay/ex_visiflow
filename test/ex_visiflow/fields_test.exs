defmodule TestFields do
  use ExVisiflow.Fields
  use TypedEctoSchema
  use ExVisiflow.TypedSchemaHelpers

  typed_embedded_schema do
    visiflow_fields()
  end

  def_new(required: :none)
end

defmodule ExVisiflow.FieldsTest do
  use ExUnit.Case, async: true

  test "when including the visiflow_fields, defaults are provided" do
    assert {:ok,
            %TestFields{
              step_index: 0,
              flow_direction: :up,
              step_mod: nil,
              step_func: :run,
              step_result: nil,
              flow_error_reason: :normal,
              wrapper_mod: nil,
              wrapper_func: nil,
            }} == TestFields.new(%{})
  end
end
