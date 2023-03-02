defmodule WorkflowEx do
  @typedoc """
  The fields required for a workflow state to function with Visiflow.
  """
  alias WorkflowEx.Fields
  import WorkflowEx.Fields, only: [is_flow_state: 1]

  @type flow_state() :: %{__flow__: WorkflowEx.Fields.t()}
  defmacro __using__(opts) do
    steps = Keyword.fetch!(opts, :steps)
    wrappers = Keyword.get(opts, :wrappers, [])

    # this code verifies that only the options expected are provided, to help catch errors
    sorted_keys = opts |> Keyword.keys() |> Enum.sort()

    ~w(steps wrappers)a
    |> List.myers_difference(sorted_keys)
    |> Keyword.get(:ins)
    |> case do
      nil ->
        :ok

      errant_keys ->
        raise KeyError, message: "Unexpected Keys: #{Enum.join(errant_keys, ",")}"
    end

    quote location: :keep do
      use GenServer, restart: :transient
      import WorkflowEx.Fields, only: [is_flow_state: 1]
      require Logger

      @spec start_link(WorkflowEx.visi_state()) :: GenServer.on_start()
      def start_link(state) when is_flow_state(state) do
        GenServer.start_link(__MODULE__, state)
      end

      @impl true
      def init(state) when is_flow_state(state) do
        {:ok, state, {:continue, :handle_init}}
      end

      def init(_), do: {:stop, :missing_flow_fields}

      @impl true
      def handle_continue(:execute_step, state) do
        with {:ok, state} <- execute_befores(state),
             {response, state} <- execute_step(state) do
          route(state)
        else
          {_before_error, state} -> route(state)
          {:stop, :invalid_return_value, state} -> {:stop, :invalid_return_value, state}
        end
      end

      @impl true
      def handle_continue(:handle_init, state) do
        {_result, state} = execute_inits(state)
        route(state)
      end

      @impl true
      def handle_continue(:handle_workflow_success, state) do
        {result, state} = execute_workflow_successes(state)

        if result != :ok do
          Logger.error("handle_workflow_success/1 did not run successfully", error: result)
        end

        {:stop, :normal, state}
      end

      @impl true
      def handle_continue(:handle_workflow_failure, state) do
        {result, state} = execute_workflow_failures(state)

        if result != :ok do
          Logger.error("handle_workflow_failure/1 did not run successfully", error: result)
        end

        {:stop, Fields.get(state, :flow_error_reason), state}
      end

      @impl true
      # If I am already rolling back, and this comes in, I need to ensure it is ignored
      def handle_info({:rollback, reason}, state) do
        Logger.info("Received message to rollback", reason: reason)

        Fields.merge(state, %{last_result: reason, lifecycle_src: :rollback})
        |> route()
      end

      @impl true
      def handle_info(message, state) do
        {_response, state} = execute_step(state, message)
        route(state)
      end

      def route(
            %{
              __flow__: %Fields{
                lifecycle_src: lifecycle_src,
                last_result: result,
                flow_direction: direction,
                step_index: step_index
              }
            } = state
          ),
          do: route(lifecycle_src, result, direction, step_index, state)

      def route(:handle_init, :ok, :up, current_step, state) when is_flow_state(state) do
        state = Fields.merge(state, %{step_func: :run, step_mod: get_step(current_step)})
        {:noreply, state, {:continue, :execute_step}}
      end

      def route(:handle_init, error, :up, _current_step, state) when is_flow_state(state) do
        state = Fields.merge(state, %{flow_error_reason: error})
        {:stop, error, state}
      end

      def route(:handle_before_step, error, :up, 0, state) when is_flow_state(state) do
        state = Fields.merge(state, %{flow_direction: :down, flow_error_reason: error, step_func: :rollback})
        {:noreply, state, {:continue, :handle_workflow_failure}}
      end

      def route(:handle_before_step, error, :up, step_index, state) when is_flow_state(state) do
        state =
          Fields.merge(state, %{
            flow_error_reason: error,
            flow_direction: :down,
            step_func: :rollback,
            step_index: step_index - 1,
            step_mod: get_step(step_index - 1)
          })

        {:noreply, state, {:continue, :execute_step}}
      end

      def route(:handle_before_step, error, :down, step_index, state) when is_flow_state(state) do
        state =
          Fields.merge(state, %{step_index: step_index - 1, step_mod: get_step(step_index - 1), step_func: :rollback})

        {:noreply, state, {:continue, :execute_step}}
      end

      def route(:step, :ok, :up, step_index, state) do
        step_index = Fields.get(state, :step_index) + 1

        case get_step(step_index) do
          nil ->
            {:noreply, state, {:continue, :handle_workflow_success}}

          step_mod ->
            state = Fields.merge(state, %{step_func: :run, step_mod: step_mod, step_index: step_index})
            {:noreply, state, {:continue, :execute_step}}
        end
      end

      def route(:step, :ok, :down, 0, state),
        do: {:noreply, state, {:continue, :handle_workflow_failure}}

      def route(:step, :ok, :down, step_index, state) do
        step_index = Fields.get(state, :step_index) - 1
        step_mod = get_step(step_index)
        state = Fields.merge(state, %{step_func: :rollback, step_mod: step_mod, step_index: step_index})
        {:noreply, state, {:continue, :execute_step}}
      end

      def route(:step, :continue, :up, _step_index, state) do
        updated_state = Fields.merge(state, %{step_func: :run_continue})
        {:noreply, updated_state}
      end

      def route(:step, :continue, :down, _step_index, state) do
        updated_state = Fields.merge(state, %{step_func: :rollback_continue})
        {:noreply, updated_state}
      end

      def route(:step, error, :up, _step_index, state) do
        updated_state = Fields.merge(state, %{flow_error_reason: error, step_func: :rollback, flow_direction: :down})
        {:noreply, updated_state, {:continue, :execute_step}}
      end

      def route(:step, error, :down, _step_index, state), do: {:stop, error, state}

      def route(:rollback, error, :up, _step_index, state) do
        # step_index won't change
        updated_state = Fields.merge(state, %{flow_error_reason: error, step_func: :rollback, flow_direction: :down})
        {:noreply, updated_state, {:continue, :execute_step}}
      end

      def route(:rollback, error, :down, _step_index, state) do
        # if we're already rolling back, ignore external folks.
        {:noreply, state}
      end

      def route(arg1, arg2, arg3, arg4, arg5) do
        raise ArgumentError, "No Route Func Matched: #{inspect([arg1, arg2, arg3, arg4, arg5])}"
      end

      @spec execute_inits(WorkflowEx.flow_state()) :: {:ok | atom, WorkflowEx.flow_state()}
      def execute_inits(state), do: WorkflowEx.execute_handlers(:handle_init, unquote(wrappers), state)
      @spec execute_befores(WorkflowEx.flow_state()) :: {:ok | atom, WorkflowEx.flow_state()}
      def execute_befores(state), do: WorkflowEx.execute_handlers(:handle_before_step, unquote(wrappers), state)
      @spec execute_workflow_successes(WorkflowEx.flow_state()) :: {:ok | atom, WorkflowEx.flow_state()}
      def execute_workflow_successes(state),
        do: WorkflowEx.execute_handlers(:handle_workflow_success, unquote(wrappers), state)

      @spec execute_workflow_failures(WorkflowEx.flow_state()) :: {:ok | atom, WorkflowEx.flow_state()}
      def execute_workflow_failures(state),
        do: WorkflowEx.execute_handlers(:handle_workflow_failure, unquote(wrappers), state)

      @spec execute_step(WorkflowEx.flow_state()) :: {:ok | :continue | atom, WorkflowEx.flow_state()}
      def execute_step(state), do: WorkflowEx.execute_step(state, [state], unquote(wrappers))
      @spec execute_step(WorkflowEx.flow_state(), atom) :: {:ok | :continue | atom, WorkflowEx.flow_state()}
      def execute_step(state, message), do: WorkflowEx.execute_step(state, [message, state], unquote(wrappers))

      # Enum.at(-1) gets the last element in the list, which is not what I want.
      defp get_step(step_index) when step_index < 0, do: nil
      defp get_step(step_index), do: Enum.at(unquote(steps), step_index)
    end
  end

  def execute_step(state, args, handlers) do
    %{step_mod: mod, step_func: func} = Fields.take(state, [:step_mod, :step_func])

    with {step_response, state} when step_response != :continue <- apply(mod, func, args),
         {after_response, state} <- execute_handlers(:handle_after_step, handlers, state) do
      response = take_first_error(step_response, after_response)
      state = Fields.merge(state, %{lifecycle_src: :step, last_result: response})
      {response, state}
    else
      {:continue, state} ->
        state = Fields.merge(state, %{lifecycle_src: :step, last_result: :continue})
        {:continue, state}
    end
  end

  # Execute the wrappers and continue running them so long as the result is always {:ok, state}
  def execute_handlers(func, mods, state)
      when is_flow_state(state) and
             func in [
               :handle_init,
               :handle_before_step,
               :handle_after_step,
               :handle_workflow_success,
               :handle_workflow_failure
             ] do
    case reduce_handlers(mods, func, state) do
      flow_state when is_flow_state(flow_state) ->
        flow_state = Fields.merge(flow_state, %{lifecycle_src: func, last_result: :ok})
        {:ok, flow_state}

      {error, flow_state} ->
        flow_state = Fields.merge(flow_state, %{lifecycle_src: func, last_result: error})
        {error, flow_state}
    end
  end

  defp reduce_handlers(mods, func, state) do
    Enum.reduce_while(mods, state, fn mod, state ->
      # state = %{state | __flow__: set_current_wrapper(state.__flow__, mod, func)}

      case apply(mod, func, [state]) do
        {:ok, state} when is_flow_state(state) ->
          # state = %{state | __flow__: clear_current_wrapper(state.__flow__)}
          {:cont, state}

        {result, %{__flow__: _} = state} when is_atom(result) ->
          {:halt, {result, state}}

        {_, _} ->
          {:halt, {:invalid_return_value, state}}
      end
    end)
  end

  def take_first_error(step_result, :ok), do: step_result
  def take_first_error(:ok, after_result), do: after_result
end
