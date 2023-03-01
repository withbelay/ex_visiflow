defmodule WorkflowEx.LifecycleHandler do
  @moduledoc """
  Provides default implementations for the lifecycle of the workflow, and marks it as implementing the appropriate behaviour
  """
  @callback handle_init(WorkflowEx.visi_state()) :: {:ok | :error | atom(), WorkflowEx.visi_state()}
  @callback handle_before_step(WorkflowEx.visi_state()) :: {:ok | :error | atom(), WorkflowEx.visi_state()}
  @callback handle_after_step(WorkflowEx.visi_state()) :: {:ok | :error | atom(), WorkflowEx.visi_state()}
  @callback handle_workflow_success(WorkflowEx.visi_state()) :: {:ok | :error | atom(), WorkflowEx.visi_state()}
  @callback handle_workflow_failure(WorkflowEx.visi_state()) :: {:ok | :error | atom(), WorkflowEx.visi_state()}
  defmacro __using__(_) do
    quote do
      @behaviour WorkflowEx.LifecycleHandler

      @impl true
      def handle_init(state), do: {:ok, state}

      @impl true
      def handle_before_step(state), do: {:ok, state}

      @impl true
      def handle_after_step(state), do: {:ok, state}

      @impl true
      def handle_workflow_success(state), do: {:ok, state}

      @impl true
      def handle_workflow_failure(state), do: {:ok, state}

      defoverridable handle_before_step: 1, handle_after_step: 1, handle_workflow_success: 1, handle_workflow_failure: 1
    end
  end
end
