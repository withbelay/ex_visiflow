defmodule WorkflowEx.TestSteps do
  alias WorkflowEx.TestSteps

  use TypedEctoSchema
  use WorkflowEx.TypedSchemaHelpers

  @primary_key false
  typed_embedded_schema do
    embeds_one :__visi__, WorkflowEx.Fields
    field(:agent, WorkflowEx.Pid, virtual: true)
    field(:steps_run, :map)
    field(:execution_order, {:array, :string})
  end

  def new do
    {:ok, agent} = StateAgent.start_link()
    new!(%{agent: agent})
  end

  def_new(
    required: :none,
    default: [
      {:steps_run, %{}},
      {:execution_order, []},
      {:__visi__, %WorkflowEx.Fields{} |> Map.from_struct()}
    ]
  )

  def run_wrapper(%TestSteps{} = state, step_module, step_func, step_result) do
    run_step(state, step_module, step_func, step_result)
  end

  @spec run_step(WorkflowEx.TestSteps.t(), atom(), atom(), atom()) :: {atom(), WorkflowEx.TestSteps.t()}
  def run_step(%TestSteps{} = state, step_module, step_func, step_result) do
    # NOTE - DO NOT CHANGE VALUES VISIFLOW OWNS - It must do that
    full_step = {step_module, step_func}

    state =
      state
      |> Map.update(:steps_run, Map.put(%{}, full_step, 1), fn current ->
        Map.update(current, full_step, 1, &(&1 + 1))
      end)
      |> Map.update(:execution_order, [full_step], fn current ->
        current ++ List.wrap(full_step)
      end)

    StateAgent.set(state.agent, state)
    {step_result, state}
  end
end

defmodule WorkflowEx.StepOk do
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

defmodule WorkflowEx.WrapperOk do
  use WorkflowEx.LifecycleHandler
  alias WorkflowEx.TestSteps

  def handle_before_step(%TestSteps{} = state) do
    TestSteps.run_wrapper(state, __MODULE__, :handle_before_step, :ok)
  end

  def handle_after_step(%TestSteps{} = state) do
    TestSteps.run_wrapper(state, __MODULE__, :handle_after_step, :ok)
  end
end

defmodule WorkflowEx.WrapperOk2 do
  use WorkflowEx.LifecycleHandler
  alias WorkflowEx.TestSteps

  def handle_before_step(%TestSteps{} = state) do
    TestSteps.run_wrapper(state, __MODULE__, :handle_before_step, :ok)
  end

  def handle_after_step(%TestSteps{} = state) do
    TestSteps.run_wrapper(state, __MODULE__, :handle_after_step, :ok)
  end
end

defmodule WorkflowEx.WrapperBeforeFailure do
  use WorkflowEx.LifecycleHandler
  alias WorkflowEx.TestSteps

  def handle_before_step(%TestSteps{} = state) do
    TestSteps.run_wrapper(state, __MODULE__, :handle_before_step, :before_error)
  end
end

defmodule WorkflowEx.WrapperAfterFailure do
  use WorkflowEx.LifecycleHandler
  alias WorkflowEx.TestSteps

  def handle_before_step(%TestSteps{} = state) do
    TestSteps.run_wrapper(state, __MODULE__, :handle_before_step, :ok)
  end

  def handle_after_step(%TestSteps{} = state) do
    TestSteps.run_wrapper(state, __MODULE__, :handle_after_step, :after_error)
  end
end

defmodule WorkflowEx.WrapperBeforeRaise do
  use WorkflowEx.LifecycleHandler
  alias WorkflowEx.TestSteps

  def handle_before_step(%TestSteps{} = state) do
    TestSteps.run_wrapper(state, __MODULE__, :handle_before_step, :ok)
    {:ok, :this_is_not_the_right_state_type}
  end
end

defmodule WorkflowEx.WrapperAfterRaise do
  use WorkflowEx.LifecycleHandler
  alias WorkflowEx.TestSteps

  def handle_before_step(%TestSteps{} = state) do
    TestSteps.run_wrapper(state, __MODULE__, :handle_before_step, :ok)
  end

  def handle_after_step(%TestSteps{} = state) do
    TestSteps.run_wrapper(state, __MODULE__, :handle_after_step, :ok)
    {:ok, :this_is_not_the_right_state_type}
  end
end
