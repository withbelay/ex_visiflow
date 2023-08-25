defmodule WorkflowEx.Observers.MessagerTest do
  use ExUnit.Case, async: true
  doctest WorkflowEx.Observers.Messager
  alias WorkflowEx.Observers.Messager
  alias WorkflowEx.Fields

  setup do
    %{state: MessagableState.new!(%{})}
  end

  test "handle_init/1", %{state: state} do
    assert Messager.handle_init(state) == :init
  end

  test "handle_before_step/1", %{state: state} do
    assert Messager.handle_before_step(state) == :before_step
  end

  test "handle_after_step/1", %{state: state} do
    assert Messager.handle_after_step(state) == :after_step
    state = %{state | __flow__: Fields.merge(state, %{last_result: :error})}
    assert Messager.handle_after_step(state) == :ok
  end

  test "handle_workflow_success/1", %{state: state} do
    assert Messager.handle_workflow_success(state) == :workflow_success
  end

  test "handle_start_rollback/1", %{state: state} do
    assert Messager.handle_start_rollback(state) == :start_rollback
  end

  test "handle_workflow_failure/1", %{state: state} do
    assert Messager.handle_workflow_failure(state) == :workflow_failure
  end
end
