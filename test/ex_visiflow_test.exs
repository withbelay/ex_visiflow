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
      state = TestSteps.new!(%{step_result: :ok, step_direction: 1})
      assert JustStart.select_next_func(state).func == :run
    end

    test "when run result is continue" do
      state = TestSteps.new!(%{step_result: :continue, step_direction: 1})
      assert JustStart.select_next_func(state).func == :run_handle_info
    end

    test "when rollback result is :ok" do
      state = TestSteps.new!(%{step_result: :ok, step_direction: -1})
      assert JustStart.select_next_func(state).func == :rollback
    end

    test "when rollback result is continue" do
      state = TestSteps.new!(%{step_result: :continue, step_direction: -1})
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

      assert {:stop, :normal, state} = SyncSuccess.execute_func(state)
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
      use ExVisiflow, steps: [ExVisiflow.StepError, ExVisiflow.StepOk2]
    end

    test "the workflow fails the first step", %{test_steps: test_steps} do
      assert {:error, state} = SyncFailure.execute_func(test_steps)
      assert state.steps_run[{ExVisiflow.StepError, :run}] == 1
      assert state.step_result == :error
      assert state.step_index == 0
    end

    test "the workflow rollsback", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncFailure.start_link(test_steps)
      # completed normally because rollback succeeded
      assert_receive {:EXIT, ^pid, :error}
      state = StateAgent.get(test_steps.agent)
      # rollback not implemented yet
      # fail "rollback not implemented yet"
      # assert state.workflow_error == :error
      # assert state.did_rollback == true
      # assert state.step_result == :ok
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
      # arrange

      # act 1
      assert {:ok, pid} = AsyncSuccess.start_link(test_steps)

      # assert
      # after the first pause-step:
      steps_run = %{
        {ExVisiflow.StepOk, :run} => 1,
        {ExVisiflow.AsyncStepOk, :run} => 1
      }

      stage1_state = %TestSteps{
        agent: test_steps.agent,
        steps_run: steps_run,
        execution_order: [{ExVisiflow.StepOk, :run}, {ExVisiflow.AsyncStepOk, :run}],
        func: :run_handle_info,
        step_index: 1,
        step_result: :continue
      }

      assert_eventually(stage1_state == AsyncSuccess.get_state(pid))

      # act 2 - continue processing
      send(pid, ExVisiflow.AsyncStepOk)

      # completed normally as expected
      assert_receive {:EXIT, ^pid, :normal}

      steps_run = Map.merge(steps_run, %{
          {ExVisiflow.AsyncStepOk, :run_handle_info} => 1
        })

      stage2_state =
        stage1_state
        |> Map.put(:steps_run, steps_run)
        |> Map.replace_lazy(:execution_order, fn exec_order ->
          exec_order ++ [{ExVisiflow.AsyncStepOk, :run_handle_info}]
        end)
        |> Map.put(:step_index, 1)
        |> Map.put(:step_result, :ok)
        |> Map.put(:func, :run_handle_info)

      assert_eventually(stage2_state == StateAgent.get(test_steps.agent))
    end
  end
  describe "Failing synchronous workflow rolls back automatically" do
    defmodule SyncFailureRollsBack do
      use ExVisiflow,
        steps: [
          ExVisiflow.StepOk,
          ExVisiflow.AsyncStepOk,
          ExVisiflow.AsyncStepOk2
        ]
    end
    test "the workflow runs, pauses, receives a cancel message, and reverses direction", %{test_steps: test_steps} do
      # arrange
      Process.flag(:trap_exit, true)

      # act 1
      assert {:ok, pid} = SyncFailureRollsBack.start_link(test_steps)

      send(pid, :rollback)

      # TODO: There's no easy way to pause this workflow to examine it's resulting state, because that state is stored in the workflow and then pitched. TestSteps would need to do it's thing, and then add the state to an agent that will outlive the workflow so I can look at its values. So the next step is to create that agent, in a setup func, and find a way to inject it into my workflow, probably a pid that is in the TestState.new, so that even after the workflow completes, I can still examine the entire flow. Once done, the test on :71 becomes much easier because it doesn't have to be sculpted in a way that pauses to allow inspection of state. I can just run it all the way through, and view the outcome.

      assert_receive {:EXIT, ^pid, :rollback}
    end
  end
end
