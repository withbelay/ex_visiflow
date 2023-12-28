defmodule WorkflowEx.OnExitHandler do
  @moduledoc """
  Provides default implementations for observing and/or altering the workflow's exit reason code
  """

  defmodule Behaviour do
    @callback on_exit(process_exit_reason :: atom, WorkflowEx.flow_state()) :: any()
  end

  import WorkflowEx.Fields, only: [is_flow_state: 1]
  @behaviour WorkflowEx.OnExitHandler.Behaviour

  @impl true
  def on_exit(process_exit_reason, state) when is_flow_state(state), do: process_exit_reason
end
