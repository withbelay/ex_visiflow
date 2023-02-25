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
      alias ExVisiflow.Fields
      require Logger

      def start_link(%unquote(state_type){} = state) do
        GenServer.start_link(__MODULE__, state)
      end

      def init(%unquote(state_type){__visi__: visi} = state) do
        state = %{state | __visi__: select_step(visi)}

        {:ok, state, {:continue, :run}}
      end

      def init(_), do: {:stop, :missing_state_fields}

      def get_state(pid), do: GenServer.call(pid, :get_state)

      def handle_continue(:run, %unquote(state_type){} = state) do
        execute_step(state) |> map_step_response_to_genserver_response()
      end

      def handle_info({:rollback, reason}, %unquote(state_type){} = state) do
        visi =
          state.__visi__
          |> Map.put(:step_result, reason)
          |> maybe_save_ultimate_flow_error(reason)
          |> select_step()

        state = %{state | __visi__: visi}

        {:noreply, state, {:continue, :run}}
      end

      def handle_info(message, %unquote(state_type){} = state) do
        execute_func(state, message) |> map_step_response_to_genserver_response()
      end

      @doc """
      before_steps and after_steps MUST be synchronous
      """
      def execute_step(%unquote(state_type){__visi__: %{step_mod: nil} = visi} = state) do
        {:stop, Map.get(visi, :flow_error_reason, :normal), state}
      end

      def execute_step(%unquote(state_type){} = state) do
        with {:ok, state} <- run_wrappers(:pre, state),
             {result, state} when result != :continue <- execute_func(state),
             {after_result, state} <- run_wrappers(:post, state),
             coalesced_result <- coalesce(result, after_result) do
          {coalesced_result, state}
        end
      end

      defp coalesce(step_result, :ok), do: step_result
      defp coalesce(:ok, after_result), do: after_result

      def execute_func(%unquote(state_type){__visi__: visi} = state, message \\ nil) do
        {result, state} =
          case is_nil(message) do
            true -> apply(visi.step_mod, visi.step_func, [state])
            false -> apply(visi.step_mod, visi.step_func, [message, state])
          end

        visi =
          state.__visi__
          |> Map.put(:step_result, result)
          |> maybe_save_ultimate_flow_error(result)
          |> select_step()

        {result, %{state | __visi__: visi}}
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

      def select_step(%Fields{step_result: nil, flow_direction: :up} = state) do
        # step_result is nil initially
        state = %{state | step_mod: get_step(state.step_index), step_func: :run}
      end

      def select_step(%Fields{step_result: :ok, flow_direction: :up} = state) do
        step_index = state.step_index + 1
        state = %{state | step_index: step_index, step_mod: get_step(step_index), step_func: :run}
      end

      def select_step(%Fields{step_result: :ok, flow_direction: :down} = state) do
        step_index = state.step_index - 1
        state = %{state | step_index: step_index, step_mod: get_step(step_index), step_func: :rollback}
      end

      def select_step(%Fields{step_result: :continue, flow_direction: :up} = state) do
        %{state | step_func: :run_handle_info}
      end

      def select_step(%Fields{step_result: :continue, flow_direction: :down} = state) do
        %{state | step_func: :rollback_handle_info}
      end

      def select_step(%Fields{} = state), do: %{state | flow_direction: :down, step_func: :rollback}

      # move to the Visiflow.Fields macro
      defp set_step_result(%Fields{} = state, reason) do
        %{state | step_result: reason}
      end

      # If we're flowing forward, and get a result that is not ok or continue, then we need
      # to save that result to the flow_error_reason, because we're about to rollback
      defp maybe_save_ultimate_flow_error(%Fields{flow_direction: :up} = state, result)
           when result not in ~w(ok continue)a do
        %{state | flow_error_reason: result}
      end

      defp maybe_save_ultimate_flow_error(%Fields{} = state, _reason), do: state

      # Enum.at(-1) gets the last element in the list, which is not what I want.
      defp get_step(step_index) when step_index < 0, do: nil
      defp get_step(step_index), do: Enum.at(unquote(steps), step_index)

      # Execute the wrappers and continue running them so long as the result is always {:ok, state}
      defp run_wrappers(func, state) when func in [:pre, :post] do
        wrapper_mods = unquote(wrappers)

        result =
          Enum.reduce_while(wrapper_mods, state, fn mod, state ->
            state = %{state | __visi__: set_current_wrapper(state.__visi__, mod, func)}

            case apply(mod, func, [state]) do
              {_, invalid_state} = invalid_response when not is_struct(invalid_state, unquote(state_type)) ->
                {:halt, {:stop, :invalid_return_value, state}}

              {:ok, state} ->
                state = %{state | __visi__: clear_current_wrapper(state.__visi__)}
                {:cont, state}

              {result, state} when is_atom(result) ->
                {:halt, {:stop, result, state}}
            end
          end)

        if is_struct(result, unquote(state_type)), do: {:ok, result}, else: result
      end

      # State must track the wrapper_mod and func. These helpers allow the func above to remain
      # at a consistent level of abstraction
      defp set_current_wrapper(%Fields{} = fields, mod, func), do: %{fields | wrapper_mod: mod, wrapper_func: func}
      defp clear_current_wrapper(%Fields{} = fields), do: %{fields | wrapper_mod: nil, wrapper_func: nil}
    end
  end
end
