defmodule WorkflowEx.Observers.Checkpointer do
  use WorkflowEx.Observer
  require Logger

  @impl true
  def handle_before_step(state), do: WorkflowEx.Checkpointable.save(state)

  @impl true
  def handle_workflow_success(state), do: WorkflowEx.Checkpointable.delete_all(state)

  def handle_workflow_failure(state), do: WorkflowEx.Checkpointable.delete_all(state)
end
