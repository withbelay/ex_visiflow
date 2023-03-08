defmodule WorkflowEx.TestSteps do
  alias WorkflowEx.TestSteps

  use TypedEctoSchema
  use WorkflowEx.TypedSchemaHelpers

  @primary_key false
  typed_embedded_schema do
    embeds_one :__flow__, WorkflowEx.Fields
    field(:agent, WorkflowEx.Pid, virtual: true)
    field(:execution_order, {:array, :string})
  end

  def new do
    {:ok, agent} = StateAgent.start_link()
    new!(%{agent: agent})
  end

  def_new(
    required: :none,
    default: [
      {:execution_order, []},
      {:__flow__, %WorkflowEx.Fields{} |> Map.from_struct()}
    ]
  )

  def run_observer(%TestSteps{} = state, step_module, step_func, step_result) do
    run_step(state, step_module, step_func, step_result)
  end

  @spec run_step(WorkflowEx.TestSteps.t(), atom(), atom(), atom()) :: {atom(), WorkflowEx.TestSteps.t()}
  def run_step(%TestSteps{} = state, step_module, step_func, step_result) do
    # NOTE - DO NOT CHANGE VALUES VISIFLOW OWNS - It must do that
    full_step = {step_module, step_func}

    agent_state =
      case StateAgent.get(state.agent) do
        %TestSteps{} = agent_state ->
          %TestSteps{
            __flow__: state.__flow__,
            execution_order: agent_state.execution_order,
            agent: agent_state.agent
          }

        _ ->
          state
      end

    agent_state =
      agent_state
      |> Map.update(:execution_order, [full_step], fn current ->
        current ++ List.wrap(full_step)
      end)

    StateAgent.set(agent_state.agent, agent_state)
    {step_result, agent_state}
  end
end

defmodule WorkflowEx.StepOk do
  use WorkflowEx.Step
  alias WorkflowEx.TestSteps
  def run(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :run, :ok)
  def rollback(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :rollback, :ok)
end

defmodule WorkflowEx.StepOk2 do
  alias WorkflowEx.TestSteps
  def run(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :run, :ok)

  def rollback(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :rollback, :ok)
end

defmodule WorkflowEx.StepError do
  alias WorkflowEx.TestSteps
  def run(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :run, :error)

  def rollback(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :rollback, :ok)
end

defmodule WorkflowEx.AsyncStepOk do
  alias WorkflowEx.TestSteps
  @spec run(WorkflowEx.TestSteps.t()) :: {atom(), WorkflowEx.TestSteps.t()}
  def run(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :run, :continue)

  def run_continue(WorkflowEx.AsyncStepOk, state) do
    TestSteps.run_step(state, __MODULE__, :run_continue, :ok)
  end

  def rollback(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :rollback, :ok)
end

defmodule WorkflowEx.AsyncStepOk2 do
  alias WorkflowEx.TestSteps
  def run(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :run, :continue)

  def run_continue(WorkflowEx.AsyncStepOk2, state) do
    TestSteps.run_step(state, __MODULE__, :run_continue, :ok)
  end

  def rollback(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :rollback, :ok)
end

defmodule WorkflowEx.AsyncStepError do
  alias WorkflowEx.TestSteps
  def run(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :run, :continue)

  def run_continue(WorkflowEx.AsyncStepError, state) do
    TestSteps.run_step(state, __MODULE__, :run_continue, :error)
  end

  def rollback(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :rollback, :ok)
end

defmodule WorkflowEx.TestObserver do
  use WorkflowEx.Observer
  alias WorkflowEx.TestSteps

  @impl true
  def handle_init(state), do: run_observer(:handle_init, state)

  def handle_before_step(%TestSteps{} = state), do: run_observer(:handle_before_step, state)

  def handle_after_step(%TestSteps{} = state), do: run_observer(:handle_after_step, state)

  @impl true
  def handle_start_rollback(state), do: run_observer(:handle_start_rollback, state)

  @impl true
  def handle_workflow_success(state), do: run_observer(:handle_workflow_success, state)

  @impl true
  def handle_workflow_failure(state), do: run_observer(:handle_workflow_failure, state)

  defp run_observer(func, state), do: TestSteps.run_observer(state, __MODULE__, func, :ok)
end

defmodule WorkflowEx.TestObserver2 do
  use WorkflowEx.Observer
  alias WorkflowEx.TestSteps

  def handle_before_step(%TestSteps{} = state) do
    TestSteps.run_observer(state, __MODULE__, :handle_before_step, :ok)
  end

  def handle_after_step(%TestSteps{} = state) do
    TestSteps.run_observer(state, __MODULE__, :handle_after_step, :ok)
  end
end

defmodule WorkflowEx.RaisingObserver do
  use WorkflowEx.Observer
  alias WorkflowEx.TestSteps

  def handle_init(%TestSteps{} = state) do
    TestSteps.run_observer(state, __MODULE__, :handle_init, :ok)
    raise RuntimeError, "init"
  end

  def handle_before_step(%TestSteps{} = state) do
    TestSteps.run_observer(state, __MODULE__, :handle_before_step, :ok)
    raise RuntimeError, "before_step"
  end

  def handle_after_step(%TestSteps{} = state) do
    TestSteps.run_observer(state, __MODULE__, :handle_after_step, :ok)
    raise RuntimeError, "after_step"
  end

  def handle_workflow_success(%TestSteps{} = state) do
    TestSteps.run_observer(state, __MODULE__, :handle_after_workflow_success, :ok)
    raise RuntimeError, "workflow_success"
  end
end
