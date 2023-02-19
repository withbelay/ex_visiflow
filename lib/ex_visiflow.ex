defmodule ExVisiflow do
  defmacro __using__(opts) do
    steps = Keyword.fetch!(opts, :steps)

    quote location: :keep do
      use GenServer, restart: :transient
      require Logger

      def start_link(%{step_index: _, step_result: _, step_wrapper: _} = state) do
        GenServer.start_link(__MODULE__, state)
      end

      def init(%{step_index: _, step_result: _, step_wrapper: _} = state) do
        {:ok, state, {:continue, :run}}
      end

      def init(_), do: {:stop, :missing_state_fields}

      def get_state(pid), do: GenServer.call(pid, :get_state)

      def handle_continue(:run, state) do
        # This needs to process a single step at a time, before deferring to other processes
        case run(state) do
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

      def run(%{step_index: step_index} = state) do
        Logger.info("Step Index: #{step_index}", label: __MODULE__)

        case Enum.at(unquote(steps), step_index) do
          nil ->
            Logger.info("FINISHED ----------- ")
            {:stop, :normal, state}

          step ->
            case apply(step, :run, [state]) do
              {:ok, state} ->
                Logger.info("Succeeded with: #{step}", label: __MODULE__)
                state = %{state | step_index: step_index + 1, step_result: :ok}
                # THIS IS ACTUALLY BAD, BECAUSE MESSAGES ARE NOT ALLOWED TO INTERJECT
                {:ok, state}

              # run(state)
              {:continue, state} ->
                Logger.info("Pausing with: #{step}", label: __MODULE__)
                state = %{state | step_result: :continue}
                {:continue, state}

              {error, state} ->
                Logger.info("Failed with: #{step}", label: __MODULE__)
                state = %{state | step_result: error}
                {error, state}
            end
        end
      end

      def run_continue(message, %{step_index: step_index} = state) do
        step = Enum.at(unquote(steps), step_index)

        case apply(step, :run_handle_info, [message, state]) do
          {:ok, state} ->
            Logger.info("Succeeded with: #{step}", label: __MODULE__)
            state = %{state | step_index: step_index + 1, step_result: :ok}
            {:ok, state}

          {:continue, state} ->
            Logger.info("Pausing with: #{step}", label: __MODULE__)
            state = %{state | step_result: :continue}
            {:continue, state}

          {error, state} ->
            Logger.info("Failed with: #{step}", label: __MODULE__)
            state = %{state | step_result: error}
            {error, state}
        end
      end

      def handle_info(:kill_it_with_fire, state) do
        {:stop, :kill_it_with_fire, state}
      end

      # This is a combination of the handle_continue and the run funcs right now. It can't be universal because
      def handle_info(message, %{step_index: step_index} = state) do
        case run_continue(message, state) do
          {:ok, state} ->
            {:noreply, state, {:continue, :run}}
          {:continue, state} ->
            {:noreply, state}
          {error, state} ->
            {:stop, error, state}
        end
      end

      def handle_call(:get_state, _from, state), do: {:reply, state, state}
    end
  end
end

#   import StepContinueOk

#   @stop_msgs [MarketAlert, TradingDown]
#   @flow [StepOk, StepContinueOk]
#   def init(_) do
#     {:ok, %{step_index: 0, last_result: :ok, direction: :up}, {:continue, :run}}
#   end

#   # def next_step(%{step_index: step_index, direction: :up), do: next_step(step_index + 1)
#   # def next_step(%{step_index: step_index, direction: :down), do: next_step(step_index - 1)
#   def next_step(step_index)
#     Enum.at(@flow, step_index)
#   end

#   def handle_continue(:run, %{step_index: step_index, last_result: :ok} = state) do
#     step = next_step(step_index)
#     Logger.info("Current State: #{inspect(state)}")
#     Logger.info("Step: #{step_index} - #{step}")
#     run(step, state)
#   end

#   def run(nil, state) do
#     Logger.info("Success - ran all the things")
#     {:stop, :success, state}
#   end

#   def run(step, %{step_index: step_index} = state) do
#     case apply(step, :run, [state]) do
#       {:ok, state} ->
#         state = %{state | step_index: step_index + 1, last_result: :ok}
#         {:noreply, state, {:continue, :run}}
#       {:continue, state} ->
#         {:noreply, state}
#       {error, state} ->
#         state = %{state | last_result: error, direction: :down}
#         Logger.error(error)
#       #   # I'll use the step_delta to run through in reverse order now
#       #   {:stop, state.error, state}
#     end
#   end

#   def handle_info(msg, state) when msg in @stop_msgs do

#   end

#   # this has to be here, otherwise every step must be a macro.
#   # This provides an internal message router.
#   def handle_info(msg, state) do
#     Logger.info("Msg rcvd: #{msg}")
#     case run_continue(msg, state) do
#       {:ok, state} ->
#         state = %{state | step_index: state.step_index + 1, last_result: :ok}
#         {:noreply, state, {:continue, :run}}
#       {error, state} ->
#         state = %{state | last_error: error}
#         {:noreply, state, {:continue, :error}}
#     end
#   end

#   handle_call(:die_immediately)
# end
