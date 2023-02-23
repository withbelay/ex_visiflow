defmodule ExVisiflowTest do
  use ExUnit.Case
  use AssertEventually, timeout: 50, interval: 5

  alias ExVisiflow.TestSteps

  doctest ExVisiflow

  setup do
    Process.flag(:trap_exit, true)
    {:ok, %{test_steps: TestSteps.new()}}
  end
  defmodule JustStart do
    use ExVisiflow, steps: []
  end

  describe "select_next_func\1" do
    test "when run result is :ok" do
      state = TestSteps.new!(%{step_result: :ok, flow_direction: :up})
      assert JustStart.select_next_func(state).func == :run
    end

    test "when run result is continue" do
      state = TestSteps.new!(%{step_result: :continue, flow_direction: :up})
      assert JustStart.select_next_func(state).func == :run_handle_info
    end

    test "when rollback result is :ok" do
      state = TestSteps.new!(%{step_result: :ok, flow_direction: :down})
      assert JustStart.select_next_func(state).func == :rollback
    end

    test "when rollback result is continue" do
      state = TestSteps.new!(%{step_result: :continue, flow_direction: :down})
      assert JustStart.select_next_func(state).func == :rollback_handle_info
    end
  end

  describe "when init-ing a workflow" do

    test "will continue to the workflow", %{test_steps: test_steps} do
      assert {:ok, test_steps, {:continue, :run}} == JustStart.init(test_steps)
    end

    test "when trying to start a workflow w/ a state that is missing the required fields, halt" do
      assert {:stop, :missing_state_fields} == JustStart.init(%{})
    end
  end

  describe "a synchronous, successful workflow with no wrapper steps or finalizer" do
    defmodule SyncSuccess do
      use ExVisiflow, steps: [ExVisiflow.StepOk, ExVisiflow.StepOk2]
    end

    test "the workflow runs a step, and returns the outcome", %{test_steps: test_steps} do
      assert {:ok, state} = SyncSuccess.execute_func(test_steps)
      assert state.steps_run[{ExVisiflow.StepOk, :run}] == 1
      assert state.execution_order == [{ExVisiflow.StepOk, :run}]

      assert {:ok, state} = SyncSuccess.execute_func(state)
      assert state.steps_run[{ExVisiflow.StepOk2, :run}] == 1
      assert state.execution_order == [{ExVisiflow.StepOk, :run}, {ExVisiflow.StepOk2, :run}]

      assert {:stop, :normal , state} == SyncSuccess.execute_func(state)
    end

    test "the GenServer workflow runs to completion and stops", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncSuccess.start_link(test_steps)
      assert_receive {:EXIT, ^pid, :normal}
      final_state = StateAgent.get(test_steps.agent)
      assert final_state.steps_run == %{
          {ExVisiflow.StepOk, :run} => 1,
          {ExVisiflow.StepOk2, :run} => 1
        }
      assert final_state.execution_order == [{ExVisiflow.StepOk, :run}, {ExVisiflow.StepOk2, :run}]
    end
  end

  describe "a synchronous, failing workflow with no wrapper steps or finalizer" do
    defmodule SyncFailure do
      use ExVisiflow, steps: [ExVisiflow.StepOk, ExVisiflow.StepError]
    end

    test "the workflow fails the first step", %{test_steps: test_steps} do
      assert {:ok, state} = SyncFailure.execute_func(test_steps)
      assert {:error, state} = SyncFailure.execute_func(state)
      assert state.steps_run[{ExVisiflow.StepError, :run}] == 1
      assert state.step_result == :error
      assert state.step_index == 1
      assert state.flow_direction == :down
    end

    test "the workflow rollsback", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncFailure.start_link(test_steps)
      # completed normally because rollback succeeded
      assert_receive {:EXIT, ^pid, :error}
      flow_state = StateAgent.get(test_steps.agent)
      assert flow_state.execution_order == [
        {ExVisiflow.StepOk, :run},
        {ExVisiflow.StepError, :run},
        {ExVisiflow.StepError, :rollback},
        {ExVisiflow.StepOk, :rollback},
      ]
    end
  end

  describe "an async, succeeding workflow with no wrapper steps or finalizer" do
    defmodule AsyncSuccess do
      use ExVisiflow,
        steps: [
          ExVisiflow.StepOk,
          ExVisiflow.AsyncStepOk
        ]
    end

    test "the workflow runs, pauses, and then succeeds when the message is received", %{test_steps: test_steps} do
      # act 1
      assert {:ok, pid} = AsyncSuccess.start_link(test_steps)

      # assert
      # after the first pause-step:
      assert_eventually([
        {ExVisiflow.StepOk, :run},
        {ExVisiflow.AsyncStepOk, :run}
      ] == StateAgent.get(test_steps.agent).execution_order)

      # act 2 - now continue processing by sending the expected continue message
      send(pid, ExVisiflow.AsyncStepOk)

      # completed normally as expected
      assert_receive {:EXIT, ^pid, :normal}

      flow_state = StateAgent.get(test_steps.agent)
      assert flow_state.execution_order == [
        {ExVisiflow.StepOk, :run},
        {ExVisiflow.AsyncStepOk, :run},
        {ExVisiflow.AsyncStepOk, :run_handle_info}
      ]
    end
  end

  describe "Failing asynchronous workflow rolls back automatically" do
    defmodule AsyncFailureRollsBack do
      use ExVisiflow,
        steps: [
          ExVisiflow.StepOk,
          ExVisiflow.AsyncStepOk,
          ExVisiflow.AsyncStepError,
        ]
    end

    test "the workflow runs, pauses, receives a cancel message, and reverses direction", %{test_steps: test_steps} do
      # act 1
      assert {:ok, pid} = AsyncFailureRollsBack.start_link(test_steps)

      send(pid, ExVisiflow.AsyncStepOk)
      send(pid, ExVisiflow.AsyncStepError)

      assert_receive {:EXIT, ^pid, :error}
      flow_state = StateAgent.get(test_steps.agent)
      assert flow_state.execution_order == [
        {ExVisiflow.StepOk, :run},
        {ExVisiflow.AsyncStepOk, :run},
        {ExVisiflow.AsyncStepOk, :run_handle_info},
        {ExVisiflow.AsyncStepError, :run},
        {ExVisiflow.AsyncStepError, :run_handle_info},
        {ExVisiflow.AsyncStepError, :rollback},
        {ExVisiflow.AsyncStepOk, :rollback},
        {ExVisiflow.StepOk, :rollback},
      ]
    end

    test "the workflow runs, and if told to rollback from a separate handler, does so w/out running any further than necessary", %{test_steps: test_steps} do
      assert {:ok, pid} = AsyncFailureRollsBack.start_link(test_steps)

      send(pid, ExVisiflow.AsyncStepOk)
      send(pid, {:rollback, :external_error})
      assert_receive {:EXIT, ^pid, :external_error}
      flow_state = StateAgent.get(test_steps.agent)
      assert flow_state.execution_order == [
        {ExVisiflow.StepOk, :run},
        {ExVisiflow.AsyncStepOk, :run},
        {ExVisiflow.AsyncStepOk, :run_handle_info},
        {ExVisiflow.AsyncStepError, :run},

        # this one is never run
        # {ExVisiflow.AsyncStepError, :run_handle_info},

        {ExVisiflow.AsyncStepError, :rollback},
        {ExVisiflow.AsyncStepOk, :rollback},
        {ExVisiflow.StepOk, :rollback},
      ]
    end
  end
end
