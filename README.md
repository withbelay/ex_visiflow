# ExVisiflow
![CI Status](https://github.com/withbelay/ex_visiflow/actions/workflows/ci.yml/badge.svg)


ExVisiflow is a macro that runs workflows of a very specific character. They process work linearly, and when any error is encountered, they then work backwards in that same manner.

Workflow steps can be synchronous or asynchronous. Workflow steps that are asynchronous will return :continue, and then expected to subscribe to whatever events are needed to complete their task.

To use, define your workflow's structure:

```
defmodule Company.Workflow do
  use ExVisiflow,
    steps: [
      Company.Step1,
      Company.Step2,
      Company.Step3
    ],
    state_type: Company.Workflow.State,
    wrappers: [Company.Wrapper]
end
```

This breaks the components of a complicated workflow into focused modules, and orchestrates them automatically. Those components are covered below:

## Workflow State

Workflow components must all operate against a shared workflow state object. But Visiflow itself must maintain state to know what to execute next.

We use Ecto, and TypedEctoSchema's wrapper to define the fields required for ExVisiflow, and it is expected that you will embed that struct into your schema as well.

```
defmodule Company.Workflow.State do
  use TypedEctoSchema
  typed_embedded_schema do
    embed_one :__visi__, ExVisiflow.Fields
    # Add fields used by the workflow steps
  end
end
```

## Steps

The workflow can either be running up or down. Up is what you hope will happen. The workflow will run until completion. For synchronous steps, only 2 functions are required, run\1 and rollback\1. The ExVisiflow.Step macro implements default no-ops of both. So in Step1, suppose no rollback is required. It can be implemented like this:

```
defmodule Company.Step1 do
  use ExVisiflow.Step
  def run(%Company.Workflow.State{}=state) do
    # do work
    # modify state
    {:ok, state}
  end
end
```

Asynchronous workflows are expected to subscribe to messages, and wait for them to come in. This is done with 2 add'l functions, run_handle_info\2, and rollback_handle_info\2. A step indicates that it is waiting on an event by returning {:continue, state}.

```
defmodule Company.Step2 do
  use ExVisiflow.Step
  def run(%Company.Workflow.State{}=state) do
    # do work
    # subscribe to an event
    Company.PubSub.subscribe(Company, :step2_run_event)
    {:continue, state}
  end

  def run_handle_info(:step2_run_event, %Company.Workflow.State{}=state) do
    # do rest of work
    Company.PubSub.unsubscribe(Company, :step2_run_event)
    {:ok, state}
  end

  def rollback(%Company.Workflow.State{}=state) do
    # undo work from run\1
    Company.PubSub.subscribe(Company, :step2_rollback_event)
    {:continue, state}
  end

  def rollback_handle_info(:step2_rollback_event, %Company.Workflow.State{}=state) do
    # do rest of work
    Company.PubSub.unsubscribe(Company, :step2_rollback_event)
    {:ok, state}
  end
end
```

## Wrappers

Wrappers are functions that must be synchronous. They are intended to run code that is orthogonal to the business case of the workflow. Logging, recording state changes, and emitting status update messages are all good uses of company wrappers. They also are allowed to modify state.

Wrappers can run before and\or after a step's run or rollback function. The semantics are slightly different.

A `pre` function must return :ok, or it will rollback the workflow without ever running the step.
A `post` function will run after a step, regardless of what the return status of that step was. But like a `pre` step, any return value other than {:ok, state} will rollback the workflow.

Wrappers in particular are likely to want to know information about the state of the workflow's execution. They can access it with the state's __visi__ struct, which maintains this information. See below.
```
defmodule Company.Wrapper do
  use ExVisiflow.Wrapper
  def pre(%Company.Workflow.State{}=state) do
    # do work intended to happen before every step
    {:ok, state}
  end

  def post(%Company.Workflow.State{}=state) do
    # do work intended to happen after every step
    {:ok, state}
  end
end
```

## ExVisiflow State

| field | type | default | description |
|---|---|---|---|
| flow_direction | atom | :up | up = running, down = rolling back|
| flow_error_reason | atom | :normal | When workflow stops, it records a reason. :normal means the workflow succeeded. Any error in run is returned here |
| step_index | integer | 0 | Keeps track of what step the workflow is on |
| step_mod | atom | nil | step module being executed |
| step_func | atom | :run | step function being executed |
| step_result | atom | nil | result of the last step |
| wrapper_mod | atom | nil | wrapper module being executed |
| wrapper_func | atom | nil | wrapper func being executed |


**TODO: Add description**

- [x] Remove the application.ex
- [x] Add wrappers
- [x] Move to embedded_schema
- [x] Add step macros
- [x] Add state type
- [x] Add wrapper macros
- [ ] Rename Wrappers to Events, and name them on_start, on_step, on_step_complete, on_workflow_success, on_workflow_fail
- [ ] Add on_success and on_fail "wrapper" steps
- [ ] Add typespecs
- [ ] Can we add protocols or something to the modules? I don't know how to make a Generic behaviour because the statetype varies - Maybe if the behaviour will only care about the %{__visi__: } key in the inputs?


## Installation

**Note:** This package is not yet available on hex.

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ex_visiflow` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_visiflow, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/ex_visiflow>.

