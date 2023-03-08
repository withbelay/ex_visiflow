defmodule WorkflowExTest do
  use ExUnit.Case
  use AssertEventually, timeout: 50, interval: 5

  alias WorkflowEx.TestSteps
  alias WorkflowEx.Fields
  alias ExUnit.CaptureLog

  doctest WorkflowEx

  setup do
    Process.flag(:trap_exit, true)
    {:ok, %{test_steps: TestSteps.new()}}
  end

  defmodule JustStart do
    use WorkflowEx, steps: [WorkflowEx.StepOk, WorkflowEx.StepOk2]
  end

  describe "route\4" do
    @first_step 0
    @last_step 1
    @second_step 1

    [
      {:handle_init, :ok, :up, @first_step, {:continue, :execute_step}, %{}},
      {:step, :ok, :up, @first_step, {:continue, :execute_step}, %{step_index: @second_step, step_func: :run}},
      {:step, :ok, :up, @last_step, {:continue, :handle_workflow_success}, %{}},
      {:step, :ok, :down, @first_step, {:continue, :handle_workflow_failure}, %{}},
      {:step, :ok, :down, @second_step, {:continue, :execute_step}, %{step_index: @first_step, step_func: :rollback}},
      {:step, :continue, :up, @first_step, :noreply, %{step_index: @first_step, step_func: :run_continue}},
      {:step, :continue, :down, @first_step, :noreply, %{step_index: @first_step, step_func: :rollback_continue}},
      {:step, :er, :up, @first_step, {:continue, :execute_start_rollback},
       %{
         step_index: @first_step,
         step_func: :rollback,
         flow_direction: :down,
         flow_error_reason: :er
       }},
      {:handle_start_rollback, :er, :down, @first_step, {:continue, :execute_step}, %{}},
      {:step, :er, :down, @first_step, {:stop, :er}, %{}},
      {:rollback, :er, :up, @first_step, {:continue, :execute_step},
       %{
         step_index: @first_step,
         step_func: :rollback,
         flow_direction: :down,
         flow_error_reason: :er
       }},
      {:rollback, :er, :down, @first_step, :noreply, %{}}
    ]
    |> Enum.map(fn {src, result, direction, current_step, expected_response, expected_state} ->
      @src src
      @result result
      @direction direction
      @current_step current_step
      @expected_response expected_response
      @expected_state expected_state

      test "src: #{src}, result: #{result}, dir: #{direction}, step: #{if current_step == @first_step, do: "first", else: "last"} should return #{inspect(expected_response)}}" do
        test_steps =
          TestSteps.new!(%{
            __flow__: %{
              lifecycle_src: @src,
              last_result: @result,
              flow_direction: @direction,
              step_index: @current_step
            }
          })

        updated_state =
          case @expected_response do
            {:continue, step} ->
              assert {:noreply, updated_state, {:continue, ^step}} = JustStart.route(test_steps)
              updated_state

            {:stop, error} ->
              assert {:stop, ^error, updated_state} = JustStart.route(test_steps)
              updated_state

            :noreply ->
              assert {:noreply, updated_state} = JustStart.route(test_steps)
              updated_state
          end

        assert @expected_state = Fields.take(updated_state, Map.keys(@expected_state))
      end
    end)
  end

  describe "when init-ing a workflow" do
    test "will continue to the workflow", %{test_steps: test_steps} do
      assert {:ok, test_steps, {:continue, :handle_init}} == JustStart.init(test_steps)
    end

    test "when trying to start a workflow w/ a state that is missing the required fields, halt" do
      assert {:stop, :missing_flow_fields} == JustStart.init(%{})
    end
  end

  describe "a synchronous, successful workflow with no observer steps or finalizer" do
    defmodule SyncSuccess do
      use WorkflowEx, steps: [WorkflowEx.StepOk, WorkflowEx.StepOk2]
    end

    test "the GenServer workflow runs to completion and stops", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncSuccess.start_link(test_steps)
      assert_receive {:EXIT, ^pid, :normal}
      final_state = StateAgent.get(test_steps.agent)

      assert final_state.execution_order == [
               {WorkflowEx.StepOk, :run},
               {WorkflowEx.StepOk2, :run}
             ]
    end
  end

  describe "a synchronous, failing workflow with no observer steps or finalizer" do
    defmodule SyncFailure do
      use WorkflowEx,
        steps: [WorkflowEx.StepOk, WorkflowEx.StepError]
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

  describe "an async, succeeding workflow with no observer steps or finalizer" do
    defmodule AsyncSuccess do
      use WorkflowEx,
        steps: [
          WorkflowEx.StepOk,
          WorkflowEx.AsyncStepOk
        ]
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
        ]
    end

    test "the workflow runs, pauses, the async step fails, and reverses direction", %{test_steps: test_steps} do
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

  describe "a synchronous, successful workflow with observer steps" do
    defmodule SyncObserverSuccess do
      use WorkflowEx,
        steps: [WorkflowEx.StepOk, WorkflowEx.StepOk2],
        observers: [WorkflowEx.TestObserver, WorkflowEx.TestObserver2]
    end

    test "observer steps are all run", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncObserverSuccess.start_link(test_steps)

      assert_receive {:EXIT, ^pid, :normal}
      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
               {WorkflowEx.TestObserver, :handle_init},
               {WorkflowEx.TestObserver, :handle_before_step},
               {WorkflowEx.TestObserver2, :handle_before_step},
               {WorkflowEx.StepOk, :run},
               {WorkflowEx.TestObserver, :handle_after_step},
               {WorkflowEx.TestObserver2, :handle_after_step},
               {WorkflowEx.TestObserver, :handle_before_step},
               {WorkflowEx.TestObserver2, :handle_before_step},
               {WorkflowEx.StepOk2, :run},
               {WorkflowEx.TestObserver, :handle_after_step},
               {WorkflowEx.TestObserver2, :handle_after_step},
               {WorkflowEx.TestObserver, :handle_workflow_success}
             ]
    end
  end

  describe "a synchronous workflow with observer steps that raise can't stop the workflow" do
    defmodule SyncObserverRaise do
      use WorkflowEx,
        steps: [WorkflowEx.StepOk],
        observers: [WorkflowEx.RaisingObserver]
    end

    test "when run", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncObserverRaise.start_link(test_steps)

      assert_receive {:EXIT, ^pid, :normal}
      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
               {WorkflowEx.RaisingObserver, :handle_init},
               {WorkflowEx.RaisingObserver, :handle_before_step},
               {WorkflowEx.StepOk, :run},
               {WorkflowEx.RaisingObserver, :handle_after_step},
               {WorkflowEx.RaisingObserver, :handle_after_workflow_success}
             ]
    end
  end

  describe "an asynchronous, successful workflow with after steps" do
    defmodule AsyncSuccessWithObservers do
      use WorkflowEx,
        steps: [WorkflowEx.AsyncStepOk],
        observers: [WorkflowEx.TestObserver]
    end

    test "the expected steps and observers all fire", %{test_steps: test_steps} do
      assert {:ok, pid} = AsyncSuccessWithObservers.start_link(test_steps)
      send(pid, WorkflowEx.AsyncStepOk)
      assert_receive {:EXIT, ^pid, :normal}

      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
               {WorkflowEx.TestObserver, :handle_init},
               {WorkflowEx.TestObserver, :handle_before_step},
               {WorkflowEx.AsyncStepOk, :run},
               {WorkflowEx.AsyncStepOk, :run_continue},
               {WorkflowEx.TestObserver, :handle_after_step},
               {WorkflowEx.TestObserver, :handle_workflow_success}
             ]
    end
  end

  describe "a synchronous, failing workflow with a working handle_workflow_failure observer" do
    defmodule SyncHandleFailureObserverSuccess do
      use WorkflowEx,
        steps: [WorkflowEx.StepError],
        observers: [WorkflowEx.TestObserver]
    end

    test "runs handle_workflow_failure successfully", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncHandleFailureObserverSuccess.start_link(test_steps)

      assert_receive {:EXIT, ^pid, :error}

      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
               {WorkflowEx.TestObserver, :handle_init},
               {WorkflowEx.TestObserver, :handle_before_step},
               {WorkflowEx.StepError, :run},
               {WorkflowEx.TestObserver, :handle_after_step},
               {WorkflowEx.TestObserver, :handle_start_rollback},
               {WorkflowEx.TestObserver, :handle_before_step},
               {WorkflowEx.StepError, :rollback},
               {WorkflowEx.TestObserver, :handle_after_step},
               {WorkflowEx.TestObserver, :handle_workflow_failure}
             ]
    end
  end

  test "in_rollback?" do
    steps =
      TestSteps.new()
      |> Fields.merge(%{direction: :up})

    refute WorkflowEx.in_rollback?(steps)

    steps = Fields.merge(steps, %{direction: :down})
    assert WorkflowEx.in_rollback?(steps)
  end
end
