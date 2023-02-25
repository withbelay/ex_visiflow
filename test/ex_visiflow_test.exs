defmodule ExVisiflowTest do
  use ExUnit.Case
  use AssertEventually, timeout: 50, interval: 5

  alias ExVisiflow.TestSteps
  alias ExVisiflow.Fields

  doctest ExVisiflow

  setup do
    Process.flag(:trap_exit, true)
    {:ok, %{test_steps: TestSteps.new()}}
  end

  defmodule JustStart do
    use ExVisiflow, steps: [], state_type: ExVisiflow.TestSteps
  end

  describe "select_step\1" do
    test "when run result is :ok" do
      state = %Fields{step_result: :ok, flow_direction: :up}
      assert JustStart.select_step(state).step_func == :run
    end

    test "when run result is continue" do
      state = %Fields{step_result: :continue, flow_direction: :up}
      assert JustStart.select_step(state).step_func == :run_handle_info
    end

    test "when rollback result is :ok" do
      state = %Fields{step_result: :ok, flow_direction: :down}
      assert JustStart.select_step(state).step_func == :rollback
    end

    test "when rollback result is continue" do
      state = %Fields{step_result: :continue, flow_direction: :down}
      assert JustStart.select_step(state).step_func == :rollback_handle_info
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
      use ExVisiflow, steps: [ExVisiflow.StepOk, ExVisiflow.StepOk2], state_type: ExVisiflow.TestSteps
    end

    test "the workflow runs a step, and returns the outcome", %{test_steps: test_steps} do
      {:ok, test_steps, _} = SyncSuccess.init(test_steps)
      assert {:ok, state} = SyncSuccess.execute_step(test_steps)
      assert state.steps_run[{ExVisiflow.StepOk, :run}] == 1
      assert state.execution_order == [{ExVisiflow.StepOk, :run}]

      assert {:ok, state} = SyncSuccess.execute_step(state)
      assert state.steps_run[{ExVisiflow.StepOk2, :run}] == 1
      assert state.execution_order == [{ExVisiflow.StepOk, :run}, {ExVisiflow.StepOk2, :run}]

      assert {:stop, :normal, state} == SyncSuccess.execute_step(state)
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
      use ExVisiflow,
        steps: [ExVisiflow.StepOk, ExVisiflow.StepError],
        state_type: ExVisiflow.TestSteps
    end

    test "the workflow fails the first step", %{test_steps: test_steps} do
      {:ok, test_steps, _} = SyncFailure.init(test_steps)
      assert {:ok, state} = SyncFailure.execute_step(test_steps)
      assert {:error, state} = SyncFailure.execute_step(state)
      visi = state.__visi__
      assert state.steps_run[{ExVisiflow.StepError, :run}] == 1
      assert visi.step_result == :error
      assert visi.step_index == 1
      assert visi.flow_direction == :down
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
               {ExVisiflow.StepOk, :rollback}
             ]
    end
  end

  describe "an async, succeeding workflow with no wrapper steps or finalizer" do
    defmodule AsyncSuccess do
      use ExVisiflow,
        steps: [
          ExVisiflow.StepOk,
          ExVisiflow.AsyncStepOk
        ],
        state_type: ExVisiflow.TestSteps
    end

    test "the workflow runs, pauses, and then succeeds when the message is received", %{test_steps: test_steps} do
      # act 1
      assert {:ok, pid} = AsyncSuccess.start_link(test_steps)

      # assert
      # after the first pause-step:
      assert_eventually(
        [
          {ExVisiflow.StepOk, :run},
          {ExVisiflow.AsyncStepOk, :run}
        ] == StateAgent.get(test_steps.agent).execution_order
      )

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
          ExVisiflow.AsyncStepError
        ],
        state_type: ExVisiflow.TestSteps
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
               {ExVisiflow.StepOk, :rollback}
             ]
    end

    test "the workflow runs, and if told to rollback from a separate handler, does so w/out running any further than necessary",
         %{test_steps: test_steps} do
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
               {ExVisiflow.StepOk, :rollback}
             ]
    end
  end

  describe "a synchronous, successful workflow with wrapper steps" do
    defmodule SyncWrapperSuccess do
      use ExVisiflow,
        steps: [ExVisiflow.StepOk, ExVisiflow.StepOk2],
        state_type: ExVisiflow.TestSteps,
        wrappers: [ExVisiflow.WrapperOk, ExVisiflow.WrapperOk2]
    end

    test "wrapper steps are all run", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncWrapperSuccess.start_link(test_steps)

      assert_receive {:EXIT, ^pid, :normal}
      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
               {ExVisiflow.WrapperOk, :pre},
               {ExVisiflow.WrapperOk2, :pre},
               {ExVisiflow.StepOk, :run},
               {ExVisiflow.WrapperOk, :post},
               {ExVisiflow.WrapperOk2, :post},
               {ExVisiflow.WrapperOk, :pre},
               {ExVisiflow.WrapperOk2, :pre},
               {ExVisiflow.StepOk2, :run},
               {ExVisiflow.WrapperOk, :post},
               {ExVisiflow.WrapperOk2, :post}
             ]
    end
  end

  describe "a synchronous workflow with before steps that fail" do
    defmodule SyncWrapperBeforeFailure do
      use ExVisiflow,
        steps: [ExVisiflow.StepOk, ExVisiflow.StepOk2],
        state_type: ExVisiflow.TestSteps,
        wrappers: [ExVisiflow.WrapperBeforeFailure]
    end

    test "wrapper steps are all run", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncWrapperBeforeFailure.start_link(test_steps)

      assert_receive {:EXIT, ^pid, :before_error}
      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
               {ExVisiflow.WrapperBeforeFailure, :pre}
             ]
    end
  end

  describe "a synchronous workflow with after steps that fail" do
    defmodule SyncWrapperAfterFailure do
      use ExVisiflow,
        steps: [ExVisiflow.StepOk, ExVisiflow.StepOk2],
        state_type: ExVisiflow.TestSteps,
        wrappers: [ExVisiflow.WrapperAfterFailure]
    end

    test "wrapper steps are all run", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncWrapperAfterFailure.start_link(test_steps)

      assert_receive {:EXIT, ^pid, :after_error}
      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
               {ExVisiflow.WrapperAfterFailure, :pre},
               {ExVisiflow.StepOk, :run},
               {ExVisiflow.WrapperAfterFailure, :post}
             ]
    end
  end

  describe "a synchronous workflow with before steps that raise" do
    defmodule SyncWrapperBeforeRaise do
      use ExVisiflow,
        steps: [ExVisiflow.StepOk, ExVisiflow.StepOk2],
        state_type: ExVisiflow.TestSteps,
        wrappers: [ExVisiflow.WrapperBeforeRaise]
    end

    test "raises when run", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncWrapperBeforeRaise.start_link(test_steps)

      assert_receive {:EXIT, ^pid, :invalid_return_value}
      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
               {ExVisiflow.WrapperBeforeRaise, :pre}
             ]
    end
  end

  describe "a synchronous workflow with after steps that raise" do
    defmodule SyncWrapperAfterRaise do
      use ExVisiflow,
        steps: [ExVisiflow.StepOk, ExVisiflow.StepOk2],
        state_type: ExVisiflow.TestSteps,
        wrappers: [ExVisiflow.WrapperAfterRaise]
    end

    test "raises when run", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncWrapperAfterRaise.start_link(test_steps)

      assert_receive {:EXIT, ^pid, :invalid_return_value}
      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
               {ExVisiflow.WrapperAfterRaise, :pre},
               {ExVisiflow.StepOk, :run},
               {ExVisiflow.WrapperAfterRaise, :post}
             ]
    end
  end
end
