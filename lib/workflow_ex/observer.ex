defmodule WorkflowEx.Observer do
  @moduledoc """
  Provides default implementations for the lifecycle of the workflow, and marks it as implementing the appropriate behaviour
  """
  @callback handle_init(WorkflowEx.flow_state()) :: any()
  @callback handle_before_step(WorkflowEx.flow_state()) :: any()
  @callback handle_after_step(WorkflowEx.flow_state()) :: any()
  @callback handle_start_rollback(WorkflowEx.flow_state()) :: any()
  @callback handle_workflow_success(WorkflowEx.flow_state()) :: any()
  @callback handle_workflow_failure(WorkflowEx.flow_state()) :: any()
  defmacro __using__(_) do
    quote do
      @behaviour WorkflowEx.Observer

      @impl true
      def handle_init(state), do: nil

      @impl true
      def handle_before_step(state), do: nil

      @impl true
      def handle_after_step(state), do: nil

      @impl true
      def handle_start_rollback(state), do: nil

      @impl true
      def handle_workflow_success(state), do: nil

      @impl true
      def handle_workflow_failure(state), do: nil

      defoverridable handle_init: 1,
                     handle_before_step: 1,
                     handle_after_step: 1,
                     handle_start_rollback: 1,
                     handle_workflow_success: 1,
                     handle_workflow_failure: 1
    end
  end
end
