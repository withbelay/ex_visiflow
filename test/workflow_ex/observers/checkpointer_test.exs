defmodule WorkflowEx.Observers.CheckpointerTest do
  use ExUnit.Case, async: true
  doctest WorkflowEx.Observers.Checkpointer
  alias WorkflowEx.Observers.Checkpointer

  setup do
    %{state: %CheckpointableState{}}
  end

  test "handle_before_step/1", %{state: state} do
    assert Checkpointer.handle_before_step(state) == :save
  end

  test "handle_workflow_success/1", %{state: state} do
    assert Checkpointer.handle_workflow_success(state) == :delete_all
  end

  test "handle_workflow_failure/1", %{state: state} do
    assert Checkpointer.handle_workflow_failure(state) == :delete_all
  end
end
