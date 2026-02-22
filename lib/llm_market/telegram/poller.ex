defmodule LlmMarket.Telegram.Poller do
  @moduledoc """
  Long-polling process for receiving Telegram updates.
  Used in development instead of webhooks.
  """

  use GenServer

  require Logger

  alias LlmMarket.Telegram.Bot

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    config = LlmMarket.telegram_config()

    if config[:bot_token] do
      Logger.info("Starting Telegram poller")
      schedule_poll(0)
      {:ok, %{offset: 0}}
    else
      Logger.warning("Telegram bot token not configured, poller not starting")
      :ignore
    end
  end

  @impl true
  def handle_info(:poll, state) do
    new_offset = poll_updates(state.offset)
    schedule_poll()
    {:noreply, %{state | offset: new_offset}}
  end

  defp poll_updates(offset) do
    params = [
      offset: offset,
      timeout: 30,
      allowed_updates: ["message", "callback_query"]
    ]

    case Telegex.get_updates(params) do
      {:ok, updates} when is_list(updates) ->
        Enum.each(updates, fn update ->
          Task.start(fn -> Bot.handle_update(update) end)
        end)

        case List.last(updates) do
          %{update_id: last_id} -> last_id + 1
          _ -> offset
        end

      {:error, reason} ->
        Logger.error("Telegram polling error: #{inspect(reason)}")
        offset
    end
  end

  defp schedule_poll(delay \\ 1000) do
    Process.send_after(self(), :poll, delay)
  end
end
