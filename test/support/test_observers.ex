defmodule WorkflowEx.TestObserver do
  use WorkflowEx.Observer
  alias WorkflowEx.TestState

  @impl true
  def handle_init(state) when is_flow_state(state), do: run_observer(:handle_init, state)

  @impl true
  def handle_before_step(state), do: run_observer(:handle_before_step, state)

  @impl true
  def handle_after_step(state), do: run_observer(:handle_after_step, state)

  @impl true
  def handle_start_rollback(state), do: run_observer(:handle_start_rollback, state)

  @impl true
  def handle_workflow_success(state), do: run_observer(:handle_workflow_success, state)

  @impl true
  def handle_workflow_failure(state), do: run_observer(:handle_workflow_failure, state)

  defp run_observer(func, state), do: TestState.run_observer(state, __MODULE__, func, :ok)
end

defmodule WorkflowEx.TestObserver2 do
  use WorkflowEx.Observer
  alias WorkflowEx.TestState

  def handle_before_step(state) do
    TestState.run_observer(state, __MODULE__, :handle_before_step, :ok)
  end

  def handle_after_step(%TestState{} = state) do
    TestState.run_observer(state, __MODULE__, :handle_after_step, :ok)
  end
end

defmodule WorkflowEx.RaisingObserver do
  use WorkflowEx.Observer
  alias WorkflowEx.TestState

  def handle_init(%TestState{} = state) do
    TestState.run_observer(state, __MODULE__, :handle_init, :ok)
    raise RuntimeError, "init"
  end

  def handle_before_step(%TestState{} = state) do
    TestState.run_observer(state, __MODULE__, :handle_before_step, :ok)
    raise RuntimeError, "before_step"
  end

  def handle_after_step(%TestState{} = state) do
    TestState.run_observer(state, __MODULE__, :handle_after_step, :ok)
    raise RuntimeError, "after_step"
  end

  def handle_workflow_success(%TestState{} = state) do
    TestState.run_observer(state, __MODULE__, :handle_after_workflow_success, :ok)
    raise RuntimeError, "workflow_success"
  end
end
