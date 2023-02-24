defmodule ExVisiflow do
  defmacro __using__(opts) do
    steps = Keyword.fetch!(opts, :steps)
    state_type = Keyword.fetch!(opts, :state_type)
    wrappers = Keyword.get(opts, :wrappers, [])

    # this code verifies that only the options expected are provided, to help catch errors
    sorted_keys = opts |> Keyword.keys() |> Enum.sort()

    ~w(state_type steps wrappers)a
    |> List.myers_difference(sorted_keys)
    |> Keyword.get(:ins)
    |> case do
      nil -> :ok
      errant_keys -> raise KeyError, message: errant_keys
    end

    quote location: :keep do
      use GenServer, restart: :transient
      require Logger

      def start_link(%unquote(state_type){} = state) do
        GenServer.start_link(__MODULE__, state)
      end

      def init(%unquote(state_type){} = state) do
        state = select_step(state)

        {:ok, state, {:continue, :run}}
      end

      def init(_), do: {:stop, :missing_state_fields}

      def get_state(pid), do: GenServer.call(pid, :get_state)

      def handle_continue(:run, %unquote(state_type){} = state) do
        execute_step(state) |> map_step_response_to_genserver_response()
      end

      def handle_info({:rollback, reason}, %unquote(state_type){} = state) do
        state =
          state
          |> Map.put(:step_result, reason)
          |> maybe_save_ultimate_flow_error(reason)
          |> select_step()

        {:noreply, state, {:continue, :run}}
      end

      def handle_info(message, %unquote(state_type){step_index: step_index} = state) do
        execute_func(state, message) |> map_step_response_to_genserver_response()
      end

      @doc """
      before_steps and after_steps MUST be synchronous
      """
      def execute_step(%unquote(state_type){step_mod: nil} = state) do
        {:stop, Map.get(state, :flow_error_reason, :normal), state}
      end

      def execute_step(%unquote(state_type){} = state) do
        # execute_func(state, message)
        with {:ok, state} <- run_wrappers(:pre, state),
             {result, state} when result != :continue <- execute_func(state),
             {after_result, state} <- run_wrappers(:post, state),
             coalesced_result <- coalesce(result, after_result) do
          {coalesced_result, state}
        end
      end

      defp coalesce(step_result, :ok), do: step_result
      defp coalesce(:ok, after_result), do: after_result

      def execute_func(%unquote(state_type){} = state, message \\ nil) do
        {result, state} =
          case is_nil(message) do
            true -> apply(state.step_mod, state.step_func, [state])
            false -> apply(state.step_mod, state.step_func, [message, state])
          end

        state =
          %{state | step_result: result}
          |> maybe_save_ultimate_flow_error(result)
          |> select_step()

        {result, state}
      end

      def map_step_response_to_genserver_response(execution_response) do
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

      def handle_call(:get_state, _from, %unquote(state_type){} = state), do: {:reply, state, state}

      def select_step(%unquote(state_type){step_result: nil, flow_direction: :up} = state) do
        # step_result is nil initially
        state = %{state | step_mod: get_step(state.step_index), step_func: :run}
      end
      def select_step(%unquote(state_type){step_result: :ok, flow_direction: :up} = state) do
        step_index = state.step_index + 1
        state = %{state | step_index: step_index, step_mod: get_step(step_index), step_func: :run}
      end
      def select_step(%unquote(state_type){step_result: :ok, flow_direction: :down} = state) do
        step_index = state.step_index - 1
        state = %{state | step_index: step_index, step_mod: get_step(step_index), step_func: :rollback}
      end
      def select_step(%unquote(state_type){step_result: :continue, flow_direction: :up} = state) do
        %{state | step_func: :run_handle_info}
      end
      def select_step(%unquote(state_type){step_result: :continue, flow_direction: :down} = state) do
        %{state | step_func: :rollback_handle_info}
      end
      def select_step(%unquote(state_type){} = state), do: %{state | flow_direction: :down, step_func: :rollback}

      # If we're flowing forward, and get a result that is not ok or continue, then we need
      # to save that result to the flow_error_reason, because we're about to rollback
      defp maybe_save_ultimate_flow_error(%unquote(state_type){flow_direction: :up} = state, result)
           when result not in ~w(ok continue)a do
        %{state | flow_error_reason: result}
      end
      defp maybe_save_ultimate_flow_error(%unquote(state_type){} = state, _reason), do: state

      # Enum.at(-1) gets the last element in the list, which is not what I want.
      defp get_step(step_index) when step_index < 0, do: nil
      defp get_step(step_index), do: Enum.at(unquote(steps), step_index)

      # Execute the wrappers and continue running them so long as the result is always {:ok, state}
      defp run_wrappers(func, state) when func in [:pre, :post] do
        wrapper_mods = unquote(wrappers)

        result =
          Enum.reduce_while(wrapper_mods, state, fn mod, state ->
            state = set_current_wrapper(state, mod, func)

            case apply(mod, func, [state]) do
              {_, invalid_state} = invalid_response when not is_struct(invalid_state, unquote(state_type)) ->
                {:halt, {:stop, :invalid_return_value, state}}

              {:ok, state} ->
                state = clear_current_wrapper(state)
                {:cont, state}

              {result, state} when is_atom(result) ->
                {:halt, {:stop, result, state}}
            end
          end)

        if is_struct(result, unquote(state_type)), do: {:ok, result}, else: result
      end

      # State must track the wrapper_mod and func. These helpers allow the func above to remain
      # at a consistent level of abstraction
      defp set_current_wrapper(state, mod, func), do: %{state | wrapper_mod: mod, wrapper_func: func}
      defp clear_current_wrapper(state), do: %{state | wrapper_mod: nil, wrapper_func: nil}
    end
  end
end
