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
        execute_func(state) |> map_response()
      end

      def handle_info(:rollback, state) do
        # Todo: This is wrong - it needs to update the state to rollback, and then :continue, :run
        {:stop, :rollback, state}
      end

      def handle_info(message, %{step_index: step_index} = state) do
        execute_func(state, message) |> map_response()
      end

      def execute_func(state, message \\ nil) do
        case get_step(state) do
          nil ->
            {:stop, Map.get(state, :flow_error_reason, :normal), state}

          step ->
            # Logger.info("Running: #{step}.#{state.func}")
            {result, state} = case is_nil(message) do
              true -> apply(step, state.func, [state])
              false -> apply(step, state.func, [message, state])
            end
            state = %{state | step_result: result }
            |> maybe_save_ultimate_flow_error(result)
            |> select_next_step()
            |> select_next_func()

            {result, state}
        end
      end

      def handle_call(:get_state, _from, state), do: {:reply, state, state}

      @doc """
      Determine which step should be run next
      """
      def select_next_step(%{step_result: :ok, flow_direction: :up} = state), do: %{ state | step_index: state.step_index + 1 }
      def select_next_step(%{step_result: :ok, flow_direction: :down} = state), do: %{ state | step_index: state.step_index - 1 }
      def select_next_step(%{step_result: :continue} = state), do: state
      def select_next_step(state), do: %{state | flow_direction: :down}

      @doc """
      Each workflow step can have up to 4 functions. This maps the visiflow state to one of them
      """
      def select_next_func(%{step_result: :ok, flow_direction: :up} = state), do: %{state | func: :run}
      def select_next_func(%{step_result: :ok, flow_direction: :down} = state), do: %{state | func: :rollback}
      def select_next_func(%{step_result: :continue, flow_direction: :up} = state), do: %{state | func: :run_handle_info}
      def select_next_func(%{step_result: :continue, flow_direction: :down} = state), do: %{state | func: :rollback_handle_info}
      def select_next_func(state), do: %{state | func: :rollback} # any other result is an error

      defp maybe_save_ultimate_flow_error(%{flow_direction: :up} = state, result) when result not in ~w(ok continue)a do
        %{state | flow_error_reason: result}
      end
      defp maybe_save_ultimate_flow_error(state, _reason), do: state

      defp get_step(%{step_index: step_index}) when step_index < 0, do: nil
      defp get_step(%{step_index: step_index}), do: Enum.at(unquote(steps), step_index)

      defp map_response(execution_response) do
        case execution_response do
          {:continue, state} ->
            {:noreply, state}

          {:stop, reason, state} ->
            {:stop, reason, state}

          {result, state} ->
            # the result's impact is already reflected in the state
            {:noreply, state, {:continue, :run}}
        end
      end
    end
  end
end
