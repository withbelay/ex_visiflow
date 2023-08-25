defmodule WorkflowEx.Observers.Messager do
  use WorkflowEx.Observer
  alias WorkflowEx.Messagable
  require Logger

  @impl true
  def handle_init(state), do: Messagable.send_message(state, :init)

  @impl true
  def handle_before_step(state), do: Messagable.send_message(state, :before_step)

  @impl true
  def handle_after_step(state) do
    case WorkflowEx.Fields.get(state, :last_result) do
      :ok -> Messagable.send_message(state, :after_step)
      _ -> :ok
    end
  end

  @impl true
  def handle_workflow_success(state), do: Messagable.send_message(state, :workflow_success)

  @impl true
  def handle_start_rollback(state), do: Messagable.send_message(state, :start_rollback)

  @impl true
  def handle_workflow_failure(state), do: Messagable.send_message(state, :workflow_failure)
end
