defmodule ExVisiflowTest do
  use ExUnit.Case
  use AssertEventually, timeout: 50, interval: 5

  alias ExVisiflow.TestSteps

  doctest ExVisiflow

  describe "when init-ing a workflow" do
    defmodule JustStart do
      use ExVisiflow, steps: []
    end

    test "will continue to the workflow" do
      assert {:ok, TestSteps.new(), {:continue, :run}} == JustStart.init(TestSteps.new())
    end

    test "when trying to start a workflow w/ a state that is missing the required fields, halt" do
      assert {:stop, :missing_state_fields} == JustStart.init(%{})
    end
  end

  describe "a synchronous, successful workflow with no wrapper steps or finalizer" do
    defmodule SyncSuccess do
      use ExVisiflow, steps: [ExVisiflow.StepOk, ExVisiflow.StepOk2]
    end

    test "the workflow runs to completion, and returns the final state" do
      assert {:ok, state} = SyncSuccess.run(TestSteps.new())
      assert state.steps_run[{ExVisiflow.StepOk, :run}] == 1
      assert state.execution_order == [{ExVisiflow.StepOk, :run}]

      assert {:ok, state} = SyncSuccess.run(state)
      assert state.steps_run[{ExVisiflow.StepOk2, :run}] == 1
      assert state.execution_order == [{ExVisiflow.StepOk, :run}, {ExVisiflow.StepOk2, :run}]

      assert {:stop, :normal, state} = SyncSuccess.run(state)
    end

    test "the GenServer workflow runs to completion and stops" do
      Process.flag(:trap_exit, true)
      assert {:ok, pid} = SyncSuccess.start_link(TestSteps.new())
      assert_receive {:EXIT, ^pid, :normal}
    end
  end

  describe "a synchronous, failing workflow with no wrapper steps or finalizer" do
    defmodule SyncFailure do
      use ExVisiflow, steps: [ExVisiflow.StepError, ExVisiflow.StepOk2]
    end

    test "the workflow runs to completion, and returns the final state" do
      assert {:error, state} = SyncFailure.run(TestSteps.new())
      assert state.steps_run[{ExVisiflow.StepError, :run}] == 1
      # it stops and does not keep running anything else
      assert is_nil(Map.get(state.steps_run, {ExVisiflow.StepOk2, :run}))
      assert state.execution_order == [{ExVisiflow.StepError, :run}]
    end
  end

  describe "an async, succeeding workflow with no wrapper steps or finalizer" do
    defmodule AsyncSuccess do
      use ExVisiflow,
        steps: [
          ExVisiflow.StepOk,
          ExVisiflow.AsyncStepOk,
          ExVisiflow.AsyncStepOk2
        ]
    end

    test "the workflow runs, pauses, and then succeeds when the message is received" do
      # arrange
      Process.flag(:trap_exit, true)

      # act 1
      assert {:ok, pid} = AsyncSuccess.start_link(TestSteps.new())

      # assert
      # after the first pause-step:
      steps_run = %{
        {ExVisiflow.StepOk, :run} => 1,
        {ExVisiflow.AsyncStepOk, :run} => 1
      }
      # steps_run =
      #   %{}
      #   |> Map.put(ExVisiflow.StepOk, 1)
      #   |> Map.put(ExVisiflow.AsyncStepOk, 1)

      stage1_state = %TestSteps{
        steps_run: steps_run,
        execution_order: [{ExVisiflow.StepOk, :run}, {ExVisiflow.AsyncStepOk, :run}],
        step_index: 1,
        step_result: :continue
      }

      assert_eventually(stage1_state == AsyncSuccess.get_state(pid))

      # act 2 - continue processing
      send(pid, ExVisiflow.AsyncStepOk)

      # after the second pause-step:
      steps_run = Map.merge(steps_run, %{
          {ExVisiflow.AsyncStepOk, :run_handle_info} => 1,
          {ExVisiflow.AsyncStepOk2, :run} => 1
        })

      stage2_state =
        stage1_state
        |> Map.put(:steps_run, steps_run)
        |> Map.replace_lazy(:execution_order, fn exec_order ->
          exec_order ++ [{ExVisiflow.AsyncStepOk, :run_handle_info}, {ExVisiflow.AsyncStepOk2, :run}]
        end)
        |> Map.put(:step_index, 2)
        |> Map.put(:step_result, :continue)

      assert_eventually(stage2_state == AsyncSuccess.get_state(pid))

      # act 3 - wrap it up
      send(pid, ExVisiflow.AsyncStepOk2)

      # completed normally as expected
      assert_receive {:EXIT, ^pid, :normal}
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
    test "the workflow runs, pauses, receives a cancel message, and reverses direction" do
      # arrange
      Process.flag(:trap_exit, true)

      # act 1
      assert {:ok, pid} = SyncFailureRollsBack.start_link(TestSteps.new())

      send(pid, :rollback)

      assert_receive {:EXIT, ^pid, :rollback}
    end
  end
end
