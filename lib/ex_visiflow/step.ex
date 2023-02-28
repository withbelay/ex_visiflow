defmodule ExVisiflow.Step do
  @moduledoc """
  Provides default implementations for step funcs, and marks it as implementing the appropriate behaviour
  """
  @callback run(ExVisiflow.visi_state()) :: {:ok | :continue | :error | atom(), ExVisiflow.visi_state()}
  @callback run_continue(ExVisiflow.visi_state(), atom()) ::
              {:ok | :continue | :error | atom(), ExVisiflow.visi_state()}
  @callback rollback(ExVisiflow.visi_state()) :: {:ok | :continue | :error | atom(), ExVisiflow.visi_state()}
  @callback rollback_continue(ExVisiflow.visi_state(), atom()) ::
              {:ok | :continue | :error | atom(), ExVisiflow.visi_state()}
  def __using__(_) do
    quote do
      @behaviour ExVisiflow.Step

      @impl true
      def run(state), do: {:ok, state}

      @impl true
      def run_continue(message, state), do: {:ok, state}

      @impl true
      def rollback(state), do: {:ok, state}

      @impl true
      def rollback_continue(messages, state), do: {:ok, state}

      defoverridable run: 1, rollback: 1, run_continue: 2, rollback_continue: 2
    end
  end
end
