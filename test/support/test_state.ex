defmodule WorkflowEx.TestState do
  alias WorkflowEx.TestState

  import WorkflowEx.Fields, only: [is_flow_state: 1]
  use TypedEctoSchema
  use WorkflowEx.TypedSchemaHelpers

  @primary_key false
  typed_embedded_schema do
    embeds_one(:__flow__, WorkflowEx.Fields)
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

  def run_observer(%TestState{} = state, step_module, step_func, step_result)
      when is_flow_state(state) do
    run_step(state, step_module, step_func, step_result)
  end

  @spec run_step(WorkflowEx.TestState.t(), atom(), atom(), atom()) ::
          {atom(), WorkflowEx.TestState.t()}
  def run_step(%TestState{} = state, step_module, step_func, step_result) do
    # NOTE - DO NOT CHANGE VALUES VISIFLOW OWNS - It must do that
    full_step = {step_module, step_func}

    agent_state =
      case StateAgent.get(state.agent) do
        %TestState{} = agent_state ->
          %TestState{
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

defmodule CheckpointableState do
  defstruct [:run]

  defimpl WorkflowEx.Checkpointable do
    def save(_state), do: :save

    def delete_all(_state), do: :delete_all
  end
end

defmodule MessagableState do
  use TypedEctoSchema
  use WorkflowEx.TypedSchemaHelpers

  @primary_key false
  typed_embedded_schema do
    embeds_one(:__flow__, WorkflowEx.Fields)
  end

  def_new(
    required: :none,
    default: [
      {:__flow__, %WorkflowEx.Fields{} |> Map.from_struct()}
    ]
  )

  defimpl WorkflowEx.Messagable do
    def send_message(_state, message), do: message
  end
end
