defmodule LlmMarket.Orchestrator.ProviderClientSupervisor do
  @moduledoc """
  Supervisor that starts a ProviderClient GenServer for each enabled provider.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children =
      LlmMarket.enabled_providers()
      |> Enum.map(fn {name, config} ->
        Supervisor.child_spec(
          {LlmMarket.Orchestrator.ProviderClient, {name, config}},
          id: {LlmMarket.Orchestrator.ProviderClient, name}
        )
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
