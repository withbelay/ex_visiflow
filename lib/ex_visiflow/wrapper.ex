defmodule ExVisiflow.Wrapper do
  @moduledoc """
  Provides default implementations for wrapper funcs, and marks it as implementing the appropriate behaviour
  """
  @callback pre(ExVisiflow.visi_state()) :: {:ok | :error | atom(), ExVisiflow.visi_state()}
  @callback post(ExVisiflow.visi_state()) :: {:ok | :error | atom(), ExVisiflow.visi_state()}
  @callback on_success(ExVisiflow.visi_state()) :: {:ok | :error | atom(), ExVisiflow.visi_state()}
  @callback on_failure(ExVisiflow.visi_state()) :: {:ok | :error | atom(), ExVisiflow.visi_state()}
  def __using__(_) do
    quote do
      @behaviour ExVisiflow.Wrapper

      @impl true
      def pre(state), do: {:ok, state}

      @impl true
      def post(state), do: {:ok, state}

      @impl true
      def on_success(state), do: {:ok, state}

      @impl true
      def on_failure(state), do: {:ok, state}
      defoverridable run: 1, rollback: 1, on_success: 1, on_failure: 1
    end
  end
end
