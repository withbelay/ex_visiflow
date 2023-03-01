defmodule WorkflowExTest do
  use ExUnit.Case
  use AssertEventually, timeout: 50, interval: 5

  alias WorkflowEx.TestSteps
  alias WorkflowEx.Fields

  doctest WorkflowEx

  setup do
    Process.flag(:trap_exit, true)
    {:ok, %{test_steps: TestSteps.new()}}
  end

  defmodule JustStart do
    use WorkflowEx, steps: [], state_type: WorkflowEx.TestSteps
  end

  describe "select_step\1" do
    test "when run result is :ok" do
      state = %Fields{step_result: :ok, flow_direction: :up}
      assert JustStart.select_step(state).step_func == :run
    end

    test "when run result is continue" do
      state = %Fields{step_result: :continue, flow_direction: :up}
      assert JustStart.select_step(state).step_func == :run_continue
    end

    test "when rollback result is :ok" do
      state = %Fields{step_result: :ok, flow_direction: :down}
      assert JustStart.select_step(state).step_func == :rollback
    end

    test "when rollback result is continue" do
      state = %Fields{step_result: :continue, flow_direction: :down}
      assert JustStart.select_step(state).step_func == :rollback_continue
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
      use WorkflowEx, steps: [WorkflowEx.StepOk, WorkflowEx.StepOk2], state_type: WorkflowEx.TestSteps
    end

    test "the workflow runs a step, and returns the outcome", %{test_steps: test_steps} do
      {:ok, test_steps, _} = SyncSuccess.init(test_steps)
      assert {:ok, state} = SyncSuccess.execute_step(test_steps)
      assert state.steps_run[{WorkflowEx.StepOk, :run}] == 1
      assert state.execution_order == [{WorkflowEx.StepOk, :run}]

      assert {:ok, state} = SyncSuccess.execute_step(state)
      assert state.steps_run[{WorkflowEx.StepOk2, :run}] == 1
      assert state.execution_order == [{WorkflowEx.StepOk, :run}, {WorkflowEx.StepOk2, :run}]

      assert {:stop, :normal, state} == SyncSuccess.execute_step(state)
    end

    test "the GenServer workflow runs to completion and stops", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncSuccess.start_link(test_steps)
      assert_receive {:EXIT, ^pid, :normal}
      final_state = StateAgent.get(test_steps.agent)

      assert final_state.steps_run == %{
               {WorkflowEx.StepOk, :run} => 1,
               {WorkflowEx.StepOk2, :run} => 1
             }

      assert final_state.execution_order == [{WorkflowEx.StepOk, :run}, {WorkflowEx.StepOk2, :run}]
    end
  end

  describe "a synchronous, failing workflow with no wrapper steps or finalizer" do
    defmodule SyncFailure do
      use WorkflowEx,
        steps: [WorkflowEx.StepOk, WorkflowEx.StepError],
        state_type: WorkflowEx.TestSteps
    end

    test "the workflow fails the first step", %{test_steps: test_steps} do
      {:ok, test_steps, _} = SyncFailure.init(test_steps)
      assert {:ok, state} = SyncFailure.execute_step(test_steps)
      assert {:error, state} = SyncFailure.execute_step(state)
      visi = state.__visi__
      assert state.steps_run[{WorkflowEx.StepError, :run}] == 1
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
               {WorkflowEx.StepOk, :run},
               {WorkflowEx.StepError, :run},
               {WorkflowEx.StepError, :rollback},
               {WorkflowEx.StepOk, :rollback}
             ]
    end
  end

  describe "an async, succeeding workflow with no wrapper steps or finalizer" do
    defmodule AsyncSuccess do
      use WorkflowEx,
        steps: [
          WorkflowEx.StepOk,
          WorkflowEx.AsyncStepOk
        ],
        state_type: WorkflowEx.TestSteps
    end

    test "the workflow runs, pauses, and then succeeds when the message is received", %{test_steps: test_steps} do
      # act 1
      assert {:ok, pid} = AsyncSuccess.start_link(test_steps)

      # assert
      # after the first pause-step:
      assert_eventually(
        [
          {WorkflowEx.StepOk, :run},
          {WorkflowEx.AsyncStepOk, :run}
        ] == StateAgent.get(test_steps.agent).execution_order
      )

      # act 2 - now continue processing by sending the expected continue message
      send(pid, WorkflowEx.AsyncStepOk)

      # completed normally as expected
      assert_receive {:EXIT, ^pid, :normal}

      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
               {WorkflowEx.StepOk, :run},
               {WorkflowEx.AsyncStepOk, :run},
               {WorkflowEx.AsyncStepOk, :run_continue}
             ]
    end
  end

  describe "Failing asynchronous workflow rolls back automatically" do
    defmodule AsyncFailureRollsBack do
      use WorkflowEx,
        steps: [
          WorkflowEx.StepOk,
          WorkflowEx.AsyncStepOk,
          WorkflowEx.AsyncStepError
        ],
        state_type: WorkflowEx.TestSteps
    end

    test "the workflow runs, pauses, receives a cancel message, and reverses direction", %{test_steps: test_steps} do
      # act 1
      assert {:ok, pid} = AsyncFailureRollsBack.start_link(test_steps)

      send(pid, WorkflowEx.AsyncStepOk)
      send(pid, WorkflowEx.AsyncStepError)

      assert_receive {:EXIT, ^pid, :error}
      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
               {WorkflowEx.StepOk, :run},
               {WorkflowEx.AsyncStepOk, :run},
               {WorkflowEx.AsyncStepOk, :run_continue},
               {WorkflowEx.AsyncStepError, :run},
               {WorkflowEx.AsyncStepError, :run_continue},
               {WorkflowEx.AsyncStepError, :rollback},
               {WorkflowEx.AsyncStepOk, :rollback},
               {WorkflowEx.StepOk, :rollback}
             ]
    end

    test "the workflow runs, and if told to rollback from a separate handler, does so w/out running any further than necessary",
         %{test_steps: test_steps} do
      assert {:ok, pid} = AsyncFailureRollsBack.start_link(test_steps)

      send(pid, WorkflowEx.AsyncStepOk)
      send(pid, {:rollback, :external_error})
      assert_receive {:EXIT, ^pid, :external_error}
      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
               {WorkflowEx.StepOk, :run},
               {WorkflowEx.AsyncStepOk, :run},
               {WorkflowEx.AsyncStepOk, :run_continue},
               {WorkflowEx.AsyncStepError, :run},

               # this one is never run
               # {WorkflowEx.AsyncStepError, :run_continue},

               {WorkflowEx.AsyncStepError, :rollback},
               {WorkflowEx.AsyncStepOk, :rollback},
               {WorkflowEx.StepOk, :rollback}
             ]
    end
  end

  describe "a synchronous, successful workflow with wrapper steps" do
    defmodule SyncWrapperSuccess do
      use WorkflowEx,
        steps: [WorkflowEx.StepOk, WorkflowEx.StepOk2],
        state_type: WorkflowEx.TestSteps,
        wrappers: [WorkflowEx.WrapperOk, WorkflowEx.WrapperOk2]
    end

    test "wrapper steps are all run", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncWrapperSuccess.start_link(test_steps)

      assert_receive {:EXIT, ^pid, :normal}
      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
               {WorkflowEx.WrapperOk, :handle_before_step},
               {WorkflowEx.WrapperOk2, :handle_before_step},
               {WorkflowEx.StepOk, :run},
               {WorkflowEx.WrapperOk, :handle_after_step},
               {WorkflowEx.WrapperOk2, :handle_after_step},
               {WorkflowEx.WrapperOk, :handle_before_step},
               {WorkflowEx.WrapperOk2, :handle_before_step},
               {WorkflowEx.StepOk2, :run},
               {WorkflowEx.WrapperOk, :handle_after_step},
               {WorkflowEx.WrapperOk2, :handle_after_step}
             ]
    end
  end

  describe "a synchronous workflow with before steps that fail" do
    defmodule SyncWrapperBeforeFailure do
      use WorkflowEx,
        steps: [WorkflowEx.StepOk, WorkflowEx.StepOk2],
        state_type: WorkflowEx.TestSteps,
        wrappers: [WorkflowEx.WrapperBeforeFailure]
    end

    test "wrapper steps are all run", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncWrapperBeforeFailure.start_link(test_steps)

      assert_receive {:EXIT, ^pid, :before_error}
      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
               {WorkflowEx.WrapperBeforeFailure, :handle_before_step}
             ]
    end
  end

  describe "a synchronous workflow with after steps that fail" do
    defmodule SyncWrapperAfterFailure do
      use WorkflowEx,
        steps: [WorkflowEx.StepOk, WorkflowEx.StepOk2],
        state_type: WorkflowEx.TestSteps,
        wrappers: [WorkflowEx.WrapperAfterFailure]
    end

    test "wrapper steps are all run", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncWrapperAfterFailure.start_link(test_steps)

      assert_receive {:EXIT, ^pid, :after_error}
      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
               {WorkflowEx.WrapperAfterFailure, :handle_before_step},
               {WorkflowEx.StepOk, :run},
               {WorkflowEx.WrapperAfterFailure, :handle_after_step}
             ]
    end
  end

  describe "a synchronous workflow with before steps that raise" do
    defmodule SyncWrapperBeforeRaise do
      use WorkflowEx,
        steps: [WorkflowEx.StepOk, WorkflowEx.StepOk2],
        state_type: WorkflowEx.TestSteps,
        wrappers: [WorkflowEx.WrapperBeforeRaise]
    end

    test "raises when run", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncWrapperBeforeRaise.start_link(test_steps)

      assert_receive {:EXIT, ^pid, :invalid_return_value}
      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
               {WorkflowEx.WrapperBeforeRaise, :handle_before_step}
             ]
    end
  end

  describe "a synchronous workflow with after steps that raise" do
    defmodule SyncWrapperAfterRaise do
      use WorkflowEx,
        steps: [WorkflowEx.StepOk, WorkflowEx.StepOk2],
        state_type: WorkflowEx.TestSteps,
        wrappers: [WorkflowEx.WrapperAfterRaise]
    end

    test "raises when run", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncWrapperAfterRaise.start_link(test_steps)

      assert_receive {:EXIT, ^pid, :invalid_return_value}
      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
               {WorkflowEx.WrapperAfterRaise, :handle_before_step},
               {WorkflowEx.StepOk, :run},
               {WorkflowEx.WrapperAfterRaise, :handle_after_step}
             ]
    end
  end
end
