defmodule WorkflowEx.Observers.Logger do
  use WorkflowEx.Observer
  require Logger

  @impl true
  def handle_init(state) when is_flow_state(state) do
    Logger.info(state: state, step: "init")
  end

  @impl true
  def handle_before_step(state) when is_flow_state(state) do
    Logger.info(state: state, step: "before_step")
  end

  @impl true
  def handle_after_step(state) when is_flow_state(state) do
    Logger.info(state: state, step: "after_step")
  end

  @impl true
  def handle_start_rollback(state) when is_flow_state(state) do
    Logger.info(state: state, step: "start_rollback")
  end

  @impl true
  def handle_workflow_success(state) when is_flow_state(state) do
    Logger.info(state: state, step: "workflow_success")
  end

  @impl true
  def handle_workflow_failure(state) when is_flow_state(state) do
    Logger.info(state: state, step: "workflow_failure")
  end
end
