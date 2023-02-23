defmodule ExVisiflow.Step do
  def __using__(_) do
    quote do
      def run(state), do: {:ok, state}
      def rollback(state), do: {:ok, state}
      defoverridable run: 1, rollback: 1
    end
  end
end
