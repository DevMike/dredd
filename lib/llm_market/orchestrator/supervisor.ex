defmodule LlmMarket.Orchestrator.Supervisor do
  @moduledoc """
  Supervisor for orchestrator components:
  - ProviderClientSupervisor (manages provider GenServers)
  - RunSupervisor (DynamicSupervisor for run coordinators)
  - Task.Supervisor for fan-out operations
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Task supervisor for parallel provider calls
      {Task.Supervisor, name: LlmMarket.Orchestrator.TaskSupervisor},

      # Dynamic supervisor for run coordinators
      {DynamicSupervisor,
       name: LlmMarket.Orchestrator.RunSupervisor, strategy: :one_for_one, max_restarts: 100},

      # Provider client supervisor
      LlmMarket.Orchestrator.ProviderClientSupervisor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
