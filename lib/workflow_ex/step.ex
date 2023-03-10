defmodule WorkflowEx.Step do
  @moduledoc """
  Provides default implementations for step funcs, and marks it as implementing the appropriate behaviour
  """
  @callback run(WorkflowEx.flow_state()) :: {:ok | :continue | :error | atom(), WorkflowEx.flow_state()}
  @callback run_continue(WorkflowEx.flow_state(), atom()) ::
              {:ok | :continue | :error | atom(), WorkflowEx.flow_state()}
  @callback rollback(WorkflowEx.flow_state()) :: {:ok | :continue | :error | atom(), WorkflowEx.flow_state()}
  @callback rollback_continue(WorkflowEx.flow_state(), atom()) ::
              {:ok | :continue | :error | atom(), WorkflowEx.flow_state()}
  defmacro __using__(_) do
    quote do
      import WorkflowEx.Fields, only: [is_flow_state: 1]
      @behaviour WorkflowEx.Step

      def run(state) when is_flow_state(state), do: {:ok, state}

      def run_continue(message, state) when is_flow_state(state), do: {:ok, state}

      def rollback(state) when is_flow_state(state), do: {:ok, state}

      def rollback_continue(messages, state) when is_flow_state(state), do: {:ok, state}

      defoverridable run: 1, rollback: 1, run_continue: 2, rollback_continue: 2
    end
  end
end
