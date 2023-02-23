defmodule StateAgent do
  def start_link(),
    do: Agent.start_link(fn -> %{} end)

  def set(pid, state) do
    Agent.update(pid, fn _ -> state end)
  end

  def get(pid) do
    Agent.get(pid, fn state -> state end)
  end
end
