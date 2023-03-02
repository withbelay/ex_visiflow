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
      {:handle_init, :ok, :up, @first_step, {:continue, :execute_step},
       %{step_mod: WorkflowEx.StepOk, step_index: @first_step, step_func: :run}},
      {:handle_init, :ok, :up, @last_step, {:continue, :execute_step},
       %{step_mod: WorkflowEx.StepOk2, step_index: @last_step, step_func: :run}},
      {:handle_init, :er, :up, @first_step, {:stop, :er}, %{flow_error_reason: :er}},
      {:handle_before_step, :er, :up, @first_step, {:continue, :handle_workflow_failure},
       %{flow_direction: :down, flow_error_reason: :er}},
      {:handle_before_step, :er, :up, @last_step, {:continue, :execute_step},
       %{
         flow_direction: :down,
         step_index: @first_step,
         step_func: :rollback,
         step_mod: WorkflowEx.StepOk,
         flow_error_reason: :er
       }},
      {:handle_before_step, :er, :down, @last_step, {:continue, :execute_step},
       %{step_index: @first_step, step_func: :rollback, step_mod: WorkflowEx.StepOk}},
      {:step, :ok, :up, @first_step, {:continue, :execute_step},
       %{step_index: @second_step, step_func: :run, step_mod: WorkflowEx.StepOk2}},
      {:step, :ok, :up, @last_step, {:continue, :handle_workflow_success}, %{}},
      {:step, :ok, :down, @first_step, {:continue, :handle_workflow_failure}, %{}},
      {:step, :ok, :down, @second_step, {:continue, :execute_step},
       %{step_index: @first_step, step_func: :rollback, step_mod: WorkflowEx.StepOk}},
      {:step, :continue, :up, @first_step, :noreply, %{step_index: @first_step, step_func: :run_continue}},
      {:step, :continue, :down, @first_step, :noreply, %{step_index: @first_step, step_func: :rollback_continue}},
      {:step, :er, :up, @first_step, {:continue, :execute_step},
       %{
         step_index: @first_step,
         step_func: :rollback,
         step_mod: WorkflowEx.StepOk,
         flow_direction: :down,
         flow_error_reason: :er
       }},
      {:step, :er, :down, @first_step, {:stop, :er}, %{}},
      {:rollback, :er, :up, @first_step, {:continue, :execute_step},
       %{
         step_index: @first_step,
         step_func: :rollback,
         step_mod: WorkflowEx.StepOk,
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
              step_index: @current_step,
              step_mod: Enum.at([WorkflowEx.StepOk, WorkflowEx.StepOk2], @current_step)
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

  describe "a synchronous, successful workflow with no wrapper steps or finalizer" do
    defmodule SyncSuccess do
      use WorkflowEx, steps: [WorkflowEx.StepOk, WorkflowEx.StepOk2], state_type: WorkflowEx.TestSteps
    end

    test "the GenServer workflow runs to completion and stops", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncSuccess.start_link(test_steps)
      assert_receive {:EXIT, ^pid, :normal}
      final_state = StateAgent.get(test_steps.agent)

      assert final_state.execution_order == [{WorkflowEx.StepOk, :run}, {WorkflowEx.StepOk2, :run}]
    end
  end

  describe "a synchronous, failing workflow with no wrapper steps or finalizer" do
    defmodule SyncFailure do
      use WorkflowEx,
        steps: [WorkflowEx.StepOk, WorkflowEx.StepError],
        state_type: WorkflowEx.TestSteps
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
               {WorkflowEx.WrapperAfterFailure, :handle_after_step},
               {WorkflowEx.WrapperAfterFailure, :handle_before_step},
               {WorkflowEx.StepOk, :rollback},
               {WorkflowEx.WrapperAfterFailure, :handle_after_step}
             ]
    end
  end

  describe "a synchronous workflow with before steps that raises" do
    defmodule SyncWrapperBeforeRaise do
      use WorkflowEx,
        steps: [WorkflowEx.StepOk, WorkflowEx.StepOk2],
        state_type: WorkflowEx.TestSteps,
        wrappers: [WorkflowEx.WrapperBeforeRaise]
    end

    test "when run", %{test_steps: test_steps} do
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
               {WorkflowEx.WrapperAfterRaise, :handle_before_step},
               {WorkflowEx.StepOk, :rollback},
               {WorkflowEx.WrapperAfterRaise, :handle_after_step}
             ]
    end
  end

  describe "an asynchronous, successful workflow with after steps" do
    defmodule AsyncSuccessWithWrappers do
      use WorkflowEx,
        steps: [WorkflowEx.AsyncStepOk],
        wrappers: [WorkflowEx.WrapperOk],
        state_type: WorkflowEx.TestSteps
    end

    test "the expected steps and wrappers all fire", %{test_steps: test_steps} do
      assert {:ok, pid} = AsyncSuccessWithWrappers.start_link(test_steps)
      send(pid, WorkflowEx.AsyncStepOk)
      assert_receive {:EXIT, ^pid, :normal}

      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
               {WorkflowEx.WrapperOk, :handle_before_step},
               {WorkflowEx.AsyncStepOk, :run},
               {WorkflowEx.AsyncStepOk, :run_continue},
               {WorkflowEx.WrapperOk, :handle_after_step}
             ]
    end
  end

  describe "a successful workflow with a working init wrapper" do
    defmodule SuccessInitWrapper do
      use WorkflowEx,
        steps: [WorkflowEx.StepOk],
        state_type: WorkflowEx.TestSteps,
        wrappers: [WorkflowEx.WrapperInitOk]
    end

    test "runs handle_init successfully", %{test_steps: test_steps} do
      assert {:ok, pid} = SuccessInitWrapper.start_link(test_steps)

      assert_receive {:EXIT, ^pid, :normal}

      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
        {WorkflowEx.WrapperInitOk, :handle_init},
        {WorkflowEx.StepOk, :run}
      ]
    end
  end

  describe "a workflow with a non-working init wrapper" do
    defmodule FailureInitWrapper do
      use WorkflowEx,
        steps: [WorkflowEx.StepOk],
        state_type: WorkflowEx.TestSteps,
        wrappers: [WorkflowEx.WrapperInitError]
    end

    test "runs handle_workflow_success successfully", %{test_steps: test_steps} do
      assert {:ok, pid} = FailureInitWrapper.start_link(test_steps)

      assert_receive {:EXIT, ^pid, :handle_init_error}

      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [{WorkflowEx.WrapperInitError, :handle_init}]
    end
  end

  describe "a synchronous, successful workflow with a non-working handle_workflow_success wrapper" do
    defmodule SyncHandleSuccessWrapperFailure do
      use WorkflowEx,
        steps: [WorkflowEx.StepOk],
        state_type: WorkflowEx.TestSteps,
        wrappers: [WorkflowEx.WrapperHandleSuccessError]
    end

    test "tries to run handle_workflow_success and logs the error", %{test_steps: test_steps} do
      {_, log} = CaptureLog.with_log(fn ->
        assert {:ok, pid} = SyncHandleSuccessWrapperFailure.start_link(test_steps)

        assert_receive {:EXIT, ^pid, :normal}
      end)

      assert log =~ "handle_workflow_success/1 did not run successfully"

      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
        {WorkflowEx.StepOk, :run},
        {WorkflowEx.WrapperHandleSuccessError, :handle_workflow_success}
      ]
    end
  end

  describe "a synchronous, failing workflow with a working handle_workflow_failure wrapper" do
    defmodule SyncHandleFailureWrapperSuccess do
      use WorkflowEx,
        steps: [WorkflowEx.StepError],
        state_type: WorkflowEx.TestSteps,
        wrappers: [WorkflowEx.WrapperHandleFailureOk]
    end

    test "runs handle_workflow_failure successfully", %{test_steps: test_steps} do
      assert {:ok, pid} = SyncHandleFailureWrapperSuccess.start_link(test_steps)

      assert_receive {:EXIT, ^pid, :error}

      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
        {WorkflowEx.StepError, :run},
        {WorkflowEx.StepError, :rollback},
        {WorkflowEx.WrapperHandleFailureOk, :handle_workflow_failure}
      ]
    end
  end

  describe "a synchronous, failing workflow with a non-working handle_workflow_failure wrapper" do
    defmodule SyncHandleFailureWrapperFailure do
      use WorkflowEx,
        steps: [WorkflowEx.StepError],
        state_type: WorkflowEx.TestSteps,
        wrappers: [WorkflowEx.WrapperHandleFailureError]
    end

    test "tries to run handle_workflow_failure and logs the error", %{test_steps: test_steps} do
      {_, log} = CaptureLog.with_log(fn ->
        assert {:ok, pid} = SyncHandleFailureWrapperFailure.start_link(test_steps)

        assert_receive {:EXIT, ^pid, :error}
      end)

      assert log =~ "handle_workflow_failure/1 did not run successfully"

      flow_state = StateAgent.get(test_steps.agent)

      assert flow_state.execution_order == [
        {WorkflowEx.StepError, :run},
        {WorkflowEx.StepError, :rollback},
        {WorkflowEx.WrapperHandleFailureError, :handle_workflow_failure}
      ]
    end
  end
end
