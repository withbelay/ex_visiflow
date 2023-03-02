      # @impl true
      # def handle_continue(:run, %unquote(state_type){} = state) do
      #   execute_step_and_handlers(state) |> map_step_response_to_genserver_response()
      # end

      # @impl true
      # def handle_info({:rollback, reason}, %unquote(state_type){} = state) do
      #   visi = Map.put(state.__visi__, :flow_error, reason)
      #   state = %{state | __visi__: visi}
      #   select_step(reason, state)
      # end

      # @impl true
      # def handle_info(message, %unquote(state_type){} = state) do
      #   execute_step_func(state, message)
      #   # needs to run the afters for the step that just ran, if continuing
      #   |> map_step_response_to_genserver_response()
      # end

      # @doc """
      # before_steps and after_steps MUST be synchronous
      # """
      # @spec execute_step_and_handlers(WorkflowEx.visi_state()) :: {:ok | :continue | :error | atom(), WorkflowEx.visi_state()}
      # def execute_step_and_handlers(%unquote(state_type){__visi__: %{step_mod: nil} = visi} = state) do
      #   {:stop, Map.get(visi, :flow_error_reason, :normal), state}
      # end

      # def execute_step_and_handlers(%unquote(state_type){} = state) do
      #   with {:ok, state} <- run_wrappers(:handle_before_step, state),
      #        {result, state} when result != :continue <- execute_step_func(state),
      #        {after_result, state} <- run_wrappers(:handle_after_step, state),
      #        coalesced_result <- coalesce(result, after_result) do
      #     {coalesced_result, state}
      #   end
      # end

      # @spec execute_step_func(WorkflowEx.visi_state(), atom()) :: {:ok | :continue | :error | atom, WorkflowEx.visi_state()}
      # def execute_step_func(%unquote(state_type){__visi__: visi} = state, message \\ nil) do
      #   {result, state} =
      #     case is_nil(message) do
      #       true -> apply(visi.step_mod, visi.step_func, [state])
      #       false -> apply(visi.step_mod, visi.step_func, [message, state])
      #     end

      #   visi =
      #     state.__visi__
      #     |> Map.put(:step_result, result)
      #     |> maybe_save_ultimate_flow_error(result)
      #     |> select_step()

      #   {result, %{state | __visi__: visi}}
      # end

      # @spec map_step_response_to_genserver_response(
      #         {:ok | :continue | atom(), WorkflowEx.visi_state()}
      #         | {:stop, :normal | :error | atom(), WorkflowEx.visi_state()}
      #       ) ::
      #         {:stop, :normal | :error | atom(), WorkflowEx.visi_state()}
      #         | {:noreply, WorkflowEx.visi_state()}
      #         | {:noreply, WorkflowEx.visi_state(), {:continue, :run}}
      # def map_step_response_to_genserver_response(execution_response) do
      #   case execution_response do
      #     {:continue, state} ->
      #       {:noreply, state}

      #     {:stop, reason, state} ->
      #       {:stop, reason, state}

      #     {result, state} ->
      #       # the result's impact is already reflected in the state
      #       {:noreply, state, {:continue, :run}}
      #   end
      # end

      # @spec select_step(WorkflowEx.Fields.t()) :: WorkflowEx.Fields.t()
      # def select_step(%Fields{step_result: nil, flow_direction: :up} = state) do
        #   # step_result is nil initially
        #   state = %{state | step_mod: get_step(state.step_index), step_func: :run}
        # end

      # def set_rollback_mode(%{__visi__: %{step_result: :ok} = visi} = state),
      #   do: %{state | __visi__: %{visi | flow_direction: :down, step_func: :rollback } }

      # def select_step(%Fields{step_result: :ok, flow_direction: :up} = state) do
      #   step_index = state.step_index + 1
      #   state = %{state | step_index: step_index, step_mod: get_step(step_index), step_func: :run}
      # end

      # def select_step(%Fields{step_result: :ok, flow_direction: :down} = state) do
      #   step_index = state.step_index - 1
      #   state = %{state | step_index: step_index, step_mod: get_step(step_index), step_func: :rollback}
      # end

      # def select_step(%Fields{step_result: :continue, flow_direction: :up} = state) do
      #   %{state | step_func: :run_continue}
      # end

      # def select_step(%Fields{step_result: :continue, flow_direction: :down} = state) do
      #   %{state | step_func: :rollback_continue}
      # end

      # def select_step(%Fields{} = state), do: %{state | flow_direction: :down, step_func: :rollback}


      # defp set_step_result(%Fields{} = state, reason) do
      #   %{state | step_result: reason}
      # end

      # If we're flowing forward, and get a result that is not ok or continue, then we need
      # to save that result to the flow_error_reason, because we're about to rollback
      # defp maybe_save_ultimate_flow_error(%Fields{flow_direction: :up} = state, result)
      #      when result not in ~w(ok continue)a do
      #   %{state | flow_error_reason: result}
      # end

      # defp maybe_save_ultimate_flow_error(%Fields{} = state, _reason), do: state

      # Enum.at(-1) gets the last element in the list, which is not what I want.
      # defp get_step(step_index) when step_index < 0, do: nil
      # defp get_step(step_index), do: Enum.at(unquote(steps), step_index)

      # Execute the wrappers and continue running them so long as the result is always {:ok, state}
