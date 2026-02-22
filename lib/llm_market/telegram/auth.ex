defmodule LlmMarket.Telegram.Auth do
  @moduledoc """
  Authorization for Telegram bot access.

  Uses a whitelist of allowed chat IDs.
  """

  require Logger

  @doc """
  Check if a chat ID is authorized to use the bot.
  """
  def authorized?(chat_id) when is_integer(chat_id) do
    whitelist = LlmMarket.telegram_config()[:whitelist_chat_ids] || MapSet.new()

    authorized = MapSet.member?(whitelist, chat_id)

    unless authorized do
      Logger.warning("Unauthorized access attempt from chat_id: #{chat_id}")
    end

    authorized
  end

  def authorized?(_), do: false
end
