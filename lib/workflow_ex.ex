defmodule WorkflowEx do
  @typedoc """
  The fields required for a workflow state to function with Visiflow.
  """
  @type flow_state() :: %{__flow__: WorkflowEx.Fields.t()}

  alias WorkflowEx.Fields
  import WorkflowEx.Fields, only: [is_flow_state: 1]

  defmacro __using__(opts) do
    steps = Keyword.fetch!(opts, :steps)
    observers = Keyword.get(opts, :observers, [])

    quote location: :keep do
      use GenServer, restart: :transient
      import WorkflowEx.Fields, only: [is_flow_state: 1]
      require Logger
      @before_compile unquote(__MODULE__)

      @spec start_link(WorkflowEx.flow_state()) :: GenServer.on_start()
      def start_link(state) when is_flow_state(state) do
        GenServer.start_link(__MODULE__, state)
      end

      defoverridable start_link: 1

      @doc """
      Starts the workflow by 'continuing' to the handle_init callback, which invokes all lifecycle handlers that
      implement handle_init
      """
      @impl true
      def init(state) when is_flow_state(state) do
        case route(state) do
          {:noreply, state, next} -> {:ok, state, next}
          otherwise -> otherwise
        end
      end

      def init(_), do: {:stop, :missing_flow_fields}

      @doc """
      Runs the handle_init funcs of all lifecycle handlers
      """
      @impl true
      def handle_continue(:handle_init, state) do
        execute_observers(:handle_init, state)

        state
        |> Fields.merge(%{lifecycle_src: :handle_init})
        |> route()
      end

      @doc """
      Executes a step, which includes:
      1. Observers's handle_before_step funcs
      2. Step's run or rollback funcs
      3. Observers's handle_after_step funcs
      https://app.clickup.com/t/860q3z5hy
      """
      @impl true
      def handle_continue(:execute_step, state) do
        execute_observers(:handle_before_step, state)

        case execute_step(state) do
          {response, state} -> route(state)
          {:stop, :invalid_return_value, state} -> {:stop, :invalid_return_value, state}
        end
      end

      @impl true
      def handle_continue(:execute_start_rollback, state) do
        execute_observers(:handle_start_rollback, state)

        state
        |> Fields.merge(%{lifecycle_src: :handle_start_rollback})
        |> route()
      end

      @doc """
      If the workflow finishes all steps successfully, it invokes the handle_workflow_success funcs of all lifecycle
      handlers
      """
      @impl true
      def handle_continue(:handle_workflow_success, state) do
        execute_observers(:handle_workflow_success, state)
        {:stop, :normal, state}
      end

      @doc """
      If the workflow errors, it invokes the handle_workflow_failure funcs of all lifecycle
      handlers after rollback completes
      """
      @impl true
      def handle_continue(:handle_workflow_failure, state) do
        execute_observers(:handle_workflow_failure, state)
        {:stop, Fields.get(state, :flow_error_reason), state}
      end

      @doc """
      If an external component sends our workflow a rollback message, it will interrupt the flow if it wasn't rolling
      back already, and undo changes as if an error had occurred due to an internal source
      """
      @impl true
      # If I am already rolling back, and this comes in, I need to ensure it is ignored
      def handle_info({:rollback, reason}, state) do
        Logger.info("Received message to rollback", reason: reason)
        execute_observers(:handle_start_rollback, state)

        Fields.merge(state, %{last_result: reason, lifecycle_src: :rollback})
        |> route()
      end

      @doc """
      The heart of WorkflowEx has to do with taking in what just happened, and what part of the lifecycle was involved,
      and determining what should happen next. The router's various overrides make these decisions
      """
      def route(
            %{
              __flow__: %Fields{
                lifecycle_src: lifecycle_src,
                last_result: result,
                flow_direction: direction,
                step_index: step_index
              }
            } = state
          ) do
        route(lifecycle_src, result, direction, step_index, state)
      end

      def route(src, result, direction, current_step, state) when is_atom(result) do
        case {src, result, direction, current_step} do
          {nil, _, :up, current_step} ->
            {:ok, state, {:continue, :handle_init}}

          {:handle_init, _, :up, current_step} ->
            {:noreply, state, {:continue, :execute_step}}

          {:step, :ok, :up, step_index} ->
            step_index = Fields.get(state, :step_index) + 1

            case get_step(step_index) do
              nil ->
                {:noreply, state, {:continue, :handle_workflow_success}}

              step_mod ->
                state = Fields.merge(state, %{step_func: :run, step_index: step_index})
                {:noreply, state, {:continue, :execute_step}}
            end

          {:step, :ok, :down, 0} ->
            {:noreply, state, {:continue, :handle_workflow_failure}}

          {:step, :ok, :down, step_index} ->
            state = Fields.merge(state, %{step_func: :rollback, step_index: step_index - 1})
            {:noreply, state, {:continue, :execute_step}}

          {:step, :continue, :up, _step_index} ->
            updated_state = Fields.merge(state, %{step_func: :run_continue})
            {:noreply, updated_state}

          {:step, :continue, :down, _step_index} ->
            updated_state = Fields.merge(state, %{step_func: :rollback_continue})
            {:noreply, updated_state}

          {:step, error, :up, _step_index} ->
            updated_state =
              Fields.merge(state, %{flow_error_reason: error, step_func: :rollback, flow_direction: :down})

            {:noreply, updated_state, {:continue, :execute_start_rollback}}

          {:handle_start_rollback, _, _, step_index} ->
            {:noreply, state, {:continue, :execute_step}}

          {:step, error, :down, _step_index} ->
            {:stop, error, state}

          {:rollback, error, :up, _step_index} ->
            # step_index won't change
            updated_state =
              Fields.merge(state, %{flow_error_reason: error, step_func: :rollback, flow_direction: :down})

            {:noreply, updated_state, {:continue, :execute_step}}

          {:rollback, error, :down, _step_index} ->
            # if a rollback step fails, we're in a bad way
            {:noreply, state}

          {arg1, arg2, arg3, arg4} ->
            raise ArgumentError, "No Route Func Matched: #{inspect([arg1, arg2, arg3, arg4])}"
        end
      end

      def route(src, result, direction, current_step, state),
        do: raise(ArgumentError, "Result was not an atom: #{inspect([src, result, direction, current_step])}")

      @spec execute_step(WorkflowEx.flow_state()) :: {:ok | :continue | atom, WorkflowEx.flow_state()}
      def execute_step(state), do: do_execute_step(state, [state])

      @spec execute_step(WorkflowEx.flow_state(), atom) :: {:ok | :continue | atom, WorkflowEx.flow_state()}
      def execute_step(state, message), do: do_execute_step(state, [message, state])

      defp do_execute_step(state, args) do
        {mod, func} = get_mod_and_func(state)

        case apply(mod, func, args) do
          {:continue, state} ->
            state = Fields.merge(state, %{lifecycle_src: :step, last_result: :continue})
            {:continue, state}

          {response, state} ->
            execute_observers(:handle_after_step, state)
            state = Fields.merge(state, %{lifecycle_src: :step, last_result: response})
            {response, state}
        end
      end

      defp get_mod_and_func(state) do
        %{step_index: step_index, step_func: func} = Fields.take(state, [:step_index, :step_func])
        mod = get_step(step_index)
        {mod, func}
      end

      def execute_observers(func, state) when is_flow_state(state) do
        Enum.each(unquote(observers), fn mod ->
          try do
            apply(mod, func, [state])
          rescue
            err -> :ok
          end
        end)
      end

      def current_step(state) when is_flow_state(state) do
        index = Fields.get(state, :step_index)
        get_step(index)
      end

      # Enum.at(-1) gets the last element in the list, which is not what I want.
      defp get_step(step_index) when step_index < 0, do: nil
      defp get_step(step_index), do: Enum.at(unquote(steps), step_index)
    end
  end

  defmacro __before_compile__(_env) do
    quote location: :keep do
      @doc """
      Async steps need to listen for something from the outside world, this func routes those messages to the step's
      listener. It's in a before_compile callback, because it catches all handle_info's. So if a workflow wants to
      register its own, they would get swallowed
      """
      @impl true
      def handle_info(message, state) do
        {_response, state} = execute_step(state, message)
        route(state)
      end
    end
  end

  def in_rollback?(state) when is_flow_state(state) do
    Fields.get(state, :flow_direction) == :down
  end

  def rollback(state, reason) when is_flow_state(state) do
    Fields.merge(state, %{last_result: reason, lifecycle_src: :rollback, step_func: :rollback})
  end
end
