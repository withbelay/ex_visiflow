defmodule ExVisiflow.TestSteps do
  alias ExVisiflow.TestSteps

  use TypedEctoSchema
  use ExVisiflow.TypedSchemaHelpers
  use ExVisiflow.Fields

  typed_embedded_schema do
    visiflow_fields()
    field(:steps_run, :map)
    field(:execution_order, {:array, :string})
  end

  @spec new :: ExVisiflow.TestSteps.t()
  def new(), do: new!(%{})
  def_new(required: :none, default: [
    {:step_index, 0},
    {:steps_run, %{}},
    {:execution_order, []},
  ])

  @spec run_step(ExVisiflow.TestSteps.t(), any, any) :: {atom(), ExVisiflow.TestSteps.t()}
  def run_step(%TestSteps{} = state, step, step_result) do
    state = state
    |> Map.put(:step_result, step_result)
    |> Map.update(:steps_run, Map.put(%{}, step, 1), fn current ->
      Map.update(current, step, 1, &(&1 + 1))
    end)
    |> Map.update(:execution_order, [step], fn current -> current ++ List.wrap(step) end)
    {step_result, state}
  end

end


defmodule ExVisiflow.StepOk do
  alias ExVisiflow.TestSteps
  def run(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :ok)
end
defmodule ExVisiflow.StepOk2 do
  alias ExVisiflow.TestSteps
  def run(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :ok)
end
defmodule ExVisiflow.StepError do
  alias ExVisiflow.TestSteps
  def run(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :error)
end
defmodule ExVisiflow.AsyncStepOk do
  alias ExVisiflow.TestSteps
  @spec run(ExVisiflow.TestSteps.t()) :: {atom(), ExVisiflow.TestSteps.t()}
  def run(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :continue)

  def run_handle_info(ExVisiflow.AsyncStepOk, state) do
    TestSteps.run_step(state, __MODULE__, :ok)
  end

end
defmodule ExVisiflow.AsyncStepOk2 do
  alias ExVisiflow.TestSteps
  def run(%TestSteps{} = state), do: TestSteps.run_step(state, __MODULE__, :continue)

  def run_handle_info(ExVisiflow.AsyncStepOk2, state) do
    TestSteps.run_step(state, __MODULE__, :ok)
  end

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
