defmodule LlmMarketWeb.WebhookController do
  use LlmMarketWeb, :controller

  require Logger

  @doc """
  Handle incoming Telegram webhook updates.
  """
  def telegram(conn, params) do
    Logger.debug("Received Telegram webhook: #{inspect(params)}")

    # Process the update asynchronously
    Task.start(fn ->
      LlmMarket.Telegram.Bot.handle_update(params)
    end)

    # Always respond quickly to Telegram
    conn
    |> put_status(200)
    |> json(%{ok: true})
  end
end
