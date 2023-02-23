defmodule ExVisiflow.TestSteps do
  alias ExVisiflow.TestSteps

  use TypedEctoSchema
  use ExVisiflow.TypedSchemaHelpers
  use ExVisiflow.Fields

  typed_embedded_schema do
    visiflow_fields()
    field(:agent, ExVisiflow.Pid, virtual: true)
    field(:steps_run, :map)
    field(:execution_order, {:array, :string})
  end

  def new() do
    {:ok, agent} = StateAgent.start_link()
    new!(%{agent: agent})
  end

  def_new(
    required: :none,
    default: [
      {:steps_run, %{}},
      {:execution_order, []}
    ]
  )

  @spec run_step(ExVisiflow.TestSteps.t(), atom(), atom(), atom()) :: {atom(), ExVisiflow.TestSteps.t()}
  def run_step(%TestSteps{} = state, step_module, step_func, step_result) do
    full_step = {step_module, step_func}
    # full_step = "#{step_module}.#{step_func}"
    state =
      %{state | step_result: step_result}
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

defmodule ExVisiflow.StepOk do
  alias ExVisiflow.TestSteps
  def run(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :run, :ok)
end

defmodule ExVisiflow.StepOk2 do
  alias ExVisiflow.TestSteps
  def run(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :run, :ok)

  def rollback(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :rollback, :ok)
end

defmodule ExVisiflow.StepError do
  alias ExVisiflow.TestSteps
  def run(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :run, :error)

  def rollback(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :rollback, :ok)
end

defmodule ExVisiflow.AsyncStepOk do
  alias ExVisiflow.TestSteps
  @spec run(ExVisiflow.TestSteps.t()) :: {atom(), ExVisiflow.TestSteps.t()}
  def run(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :run, :continue)

  def run_handle_info(ExVisiflow.AsyncStepOk, state) do
    TestSteps.run_step(state, __MODULE__, :run_handle_info, :ok)
  end

  def rollback(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :rollback, :ok)
end

defmodule ExVisiflow.AsyncStepOk2 do
  alias ExVisiflow.TestSteps
  def run(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :run, :continue)

  def run_handle_info(ExVisiflow.AsyncStepOk2, state) do
    TestSteps.run_step(state, __MODULE__, :run_handle_info, :ok)
  end

  def rollback(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :rollback, :ok)
end

# defmodule ExVisiflow.StepError do
#   alias ExVisiflow.TestSteps
#   def run(%TestSteps{} = state) do

#     {:error, Map.put(state, __MODULE__, true)}
#   end
# end

# defmodule ExVisiflow.StepContinueOk do
#   require Logger
#   # :ok, :error, :continue
#   @spec run(term) :: {[:ok | :continue | atom()], term}
#   def run(state) do
#     {:continue, state}
#   end

#   def run_handle_info(:step_continue_ok_message, state) do
#     Logger.info("#{__MODULE__} run continue")
#     {:ok, Map.put(state, __MODULE__, true)}
#   end

#   def rollback(state) do

#   end
#   def rollback_handle_info(state) do

#   end
# end