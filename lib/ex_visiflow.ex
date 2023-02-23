defmodule ExVisiflow do
  defmacro __using__(opts) do
    steps = Keyword.fetch!(opts, :steps)

    quote location: :keep do
      use GenServer, restart: :transient
      require Logger

      def start_link(%{step_index: _, step_result: _} = state) do
        GenServer.start_link(__MODULE__, state)
      end

      def init(%{step_index: _, step_result: _} = state) do
        {:ok, state, {:continue, :run}}
      end

      def init(_), do: {:stop, :missing_state_fields}

      def get_state(pid), do: GenServer.call(pid, :get_state)

      def handle_continue(:run, state) do
        execute_func(state)
        |> map_response()
      end

      def handle_info(:rollback, state) do
        {:stop, :rollback, state}
      end

      # This is a combination of the handle_continue and the run funcs right now. It can't be universal because
      def handle_info(message, %{step_index: step_index} = state) do
        execute_func(state, message)
        |> map_response()
      end

      def execute_func(state, message \\ nil) do
        case get_step(state) do
          nil ->
            {:stop, :normal, state}

          step ->
            {result, state} = case is_nil(message) do
              true -> apply(step, state.func, [state])
              false -> apply(step, state.func, [message, state])
            end
            state = %{state | step_result: result }
            |> select_next_step()
            |> select_next_func()

            {result, state}
        end
      end

      def handle_call(:get_state, _from, state), do: {:reply, state, state}

      @doc """
      Determine which step should be run next
      """
      def select_next_step(%{step_result: :ok} = state), do: %{ state | step_index: state.step_index + state.step_direction }
      def select_next_step(%{step_result: :continue} = state), do: state
      def select_next_step(state), do: %{state | step_direction: -1}

      @doc """
      Each workflow step can have up to 4 functions.
      * run
      * run_handle_info
      * rollback
      * rollback_handle_info
      """
      def select_next_func(%{step_result: :ok, step_direction: 1} = state), do: %{state | func: :run}
      def select_next_func(%{step_result: :continue, step_direction: 1} = state),
        do: %{state | func: :run_handle_info}
      def select_next_func(%{step_result: :ok, step_direction: -1} = state), do: %{state | func: :rollback}
      def select_next_func(%{step_result: :continue, step_direction: -1} = state),
        do: %{state | func: :rollback_handle_info}
      def select_next_func(state),
        do: %{state | func: :rollback}

      defp get_step(%{step_index: step_index}), do: Enum.at(unquote(steps), step_index)

      defp map_response(execution_response) do
        case execution_response do
          {:ok, state} ->
            {:noreply, state, {:continue, :run}}

          {:continue, state} ->
            {:noreply, state}

          {:stop, reason, state} ->
            {:stop, reason, state}

          {error, state} ->
            {:stop, error, state}
        end
      end
    end
  end
end