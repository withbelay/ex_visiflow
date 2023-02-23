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
    assert {:ok, %TestFields{
      step_index: 0,
      step_direction: 1,
      func: :run,
      step_result: nil
    }} == TestFields.new(%{})

  end
end
