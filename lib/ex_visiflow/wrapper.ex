defmodule ExVisiflow.Wrapper do
  def __using__(_) do
    quote do
      def pre(state), do: {:ok, state}
      def post(state), do: {:ok, state}
      # Note: These are not yet run
      def on_success(state), do: {:ok, state}
      def on_failure(state), do: {:ok, state}
      defoverridable run: 1, rollback: 1, on_success: 1, on_failure: 1
    end
  end
end
