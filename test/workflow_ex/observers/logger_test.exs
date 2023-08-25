defmodule WorkflowEx.Observers.LoggerTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias WorkflowEx.TestState

  setup do
    Process.flag(:trap_exit, true)
    {:ok, %{test_steps: TestState.new()}}
  end

  describe "LoggerTest" do
    defmodule SuccessfulLoggingObserverTest do
      use WorkflowEx,
        steps: [WorkflowEx.StepOk, WorkflowEx.StepOk2],
        observers: [WorkflowEx.Observers.Logger]
    end

    test "Logger logs the things on success", %{test_steps: test_steps} do
      log =
        capture_log([format: "$time JEFFF $metadata: $message\n"], fn ->
          assert {:ok, pid} = SuccessfulLoggingObserverTest.start_link(test_steps)
          assert_receive {:EXIT, ^pid, :normal}
        end)

      assert log =~ "init"
      assert log =~ "before_step"
      assert log =~ "after_step"
      assert log =~ "workflow_success"
    end
  end
end
