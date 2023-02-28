defmodule ExVisiflow.LifecycleHandler do
  @moduledoc """
  Provides default implementations for the lifecycle of the workflow, and marks it as implementing the appropriate behaviour
  """
  @callback handle_init(ExVisiflow.visi_state()) :: {:ok | :error | atom(), ExVisiflow.visi_state()}
  @callback handle_before_step(ExVisiflow.visi_state()) :: {:ok | :error | atom(), ExVisiflow.visi_state()}
  @callback handle_after_step(ExVisiflow.visi_state()) :: {:ok | :error | atom(), ExVisiflow.visi_state()}
  @callback handle_success(ExVisiflow.visi_state()) :: {:ok | :error | atom(), ExVisiflow.visi_state()}
  @callback handle_failure(ExVisiflow.visi_state()) :: {:ok | :error | atom(), ExVisiflow.visi_state()}
  def __using__(_) do
    quote do
      @behaviour ExVisiflow.LifecycleHandler

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
