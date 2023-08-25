defmodule WorkflowEx.StepOk do
  use WorkflowEx.Step
  alias WorkflowEx.TestState

  @impl true
  def run(%TestState{} = state), do: TestState.run_step(state, __MODULE__, :run, :ok)

  @impl true
  def rollback(%TestState{} = state), do: TestState.run_step(state, __MODULE__, :rollback, :ok)
end

defmodule WorkflowEx.StepOk2 do
  use WorkflowEx.Step
  alias WorkflowEx.TestState
  @impl true
  def run(%TestState{} = state), do: TestState.run_step(state, __MODULE__, :run, :ok)

  @impl true
  def rollback(%TestState{} = state), do: TestState.run_step(state, __MODULE__, :rollback, :ok)
end

defmodule WorkflowEx.StepError do
  use WorkflowEx.Step
  alias WorkflowEx.TestState
  @impl true
  def run(%TestState{} = state), do: TestState.run_step(state, __MODULE__, :run, :error)

  @impl true
  def rollback(%TestState{} = state), do: TestState.run_step(state, __MODULE__, :rollback, :ok)
end

defmodule WorkflowEx.AsyncStepOk do
  use WorkflowEx.Step
  alias WorkflowEx.TestState

  @impl true
  def run(%TestState{} = state), do: TestState.run_step(state, __MODULE__, :run, :continue)

  @impl true
  def run_continue(WorkflowEx.AsyncStepOk, state) do
    TestState.run_step(state, __MODULE__, :run_continue, :ok)
  end

  @impl true
  def rollback(%TestState{} = state), do: TestState.run_step(state, __MODULE__, :rollback, :ok)
end

defmodule WorkflowEx.AsyncStepOk2 do
  use WorkflowEx.Step
  alias WorkflowEx.TestState

  @impl true
  def run(%TestState{} = state), do: TestState.run_step(state, __MODULE__, :run, :continue)

  @impl true
  def run_continue(WorkflowEx.AsyncStepOk2, state) do
    TestState.run_step(state, __MODULE__, :run_continue, :ok)
  end

  @impl true
  def rollback(%TestState{} = state), do: TestState.run_step(state, __MODULE__, :rollback, :ok)
end

defmodule WorkflowEx.AsyncStepError do
  use WorkflowEx.Step
  alias WorkflowEx.TestState

  @impl true
  def run(%TestState{} = state), do: TestState.run_step(state, __MODULE__, :run, :continue)

  @impl true
  def run_continue(WorkflowEx.AsyncStepError, state) do
    TestState.run_step(state, __MODULE__, :run_continue, :error)
  end

  @impl true
  def rollback(%TestState{} = state), do: TestState.run_step(state, __MODULE__, :rollback, :ok)
end
