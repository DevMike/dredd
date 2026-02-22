defmodule LlmMarket.Telegram.Bot do
  @moduledoc """
  Telegram bot interface using Telegex.

  Handles incoming updates and dispatches to command handlers.
  """

  require Logger

  alias LlmMarket.Telegram.{Auth, Commands}

  @doc """
  Handle an incoming Telegram update.
  Telegex returns typed structs with atom keys.
  """
  def handle_update(%{message: message}) when not is_nil(message) do
    chat_id = message.chat.id

    # Check authorization
    if Auth.authorized?(chat_id) do
      process_message(message)
    else
      send_message(chat_id, "Not authorized. Contact the bot administrator.")
    end
  end

  def handle_update(%{callback_query: callback}) when not is_nil(callback) do
    chat_id = callback.message.chat.id

    if Auth.authorized?(chat_id) do
      process_callback(callback)
    else
      answer_callback(callback.id, "Not authorized")
    end
  end

  def handle_update(_update) do
    # Ignore other update types
    :ok
  end

  defp process_message(%{text: text, chat: chat}) when is_binary(text) do
    chat_id = chat.id
    # Strip @botname suffix from commands (used in groups)
    text = Regex.replace(~r/@\w+/, text, "", global: false)

    cond do
      String.starts_with?(text, "/ask ") ->
        question = String.trim_leading(text, "/ask ")
        Commands.handle_ask(chat_id, question)

      text == "/last" ->
        Commands.handle_last(chat_id)

      String.starts_with?(text, "/run ") ->
        run_id = String.trim_leading(text, "/run ")
        Commands.handle_run(chat_id, run_id)

      String.starts_with?(text, "/raw ") ->
        run_id = String.trim_leading(text, "/raw ")
        Commands.handle_raw(chat_id, run_id)

      String.starts_with?(text, "/conflicts ") ->
        run_id = String.trim_leading(text, "/conflicts ")
        Commands.handle_conflicts(chat_id, run_id)

      String.starts_with?(text, "/dredd ") ->
        dredd = String.trim_leading(text, "/dredd ")
        Commands.handle_dredd(chat_id, dredd)

      text == "/providers" ->
        Commands.handle_providers(chat_id)

      text == "/config" ->
        Commands.handle_config(chat_id)

      text == "/cancel" ->
        Commands.handle_cancel(chat_id)

      text == "/status" ->
        Commands.handle_status(chat_id)

      text in ["/help", "/start"] ->
        Commands.handle_help(chat_id)

      String.starts_with?(text, "/") ->
        send_message(chat_id, "Unknown command. Use /help to see available commands.")

      true ->
        # Not a command, could be a follow-up question in the future
        :ok
    end
  end

  defp process_message(_), do: :ok

  defp process_callback(%{id: callback_id, data: data, message: message}) do
    chat_id = message.chat.id

    case String.split(data, ":") do
      ["conflicts", run_id] ->
        Commands.handle_conflicts(chat_id, run_id)

      ["raw", run_id] ->
        Commands.handle_raw(chat_id, run_id)

      ["rerun", run_id] ->
        Commands.handle_rerun(chat_id, run_id)

      ["cost", run_id] ->
        Commands.handle_cost(chat_id, run_id)

      _ ->
        :ok
    end

    answer_callback(callback_id, nil)
  end

  @doc """
  Send a message to a chat.
  """
  def send_message(chat_id, text, opts \\ []) do
    # Use plain text by default for reliability
    optional_params =
      if opts[:parse_mode] do
        [parse_mode: opts[:parse_mode]]
      else
        []
      end
      |> maybe_add_keyboard(opts[:reply_markup])

    case Telegex.send_message(chat_id, text, optional_params) do
      {:ok, _message} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to send Telegram message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Edit a message.
  """
  def edit_message(chat_id, message_id, text, opts \\ []) do
    params =
      [
        chat_id: chat_id,
        message_id: message_id,
        text: text
      ]
      |> maybe_add_keyboard(opts[:reply_markup])

    case Telegex.edit_message_text(params) do
      {:ok, _message} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to edit Telegram message: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("Failed to edit Telegram message: #{inspect(e)}")
      {:error, e}
  end

  defp answer_callback(callback_id, text) do
    optional = if text, do: [text: text], else: []
    Telegex.answer_callback_query(callback_id, optional)
  end

  defp maybe_add_keyboard(params, nil), do: params

  defp maybe_add_keyboard(params, keyboard) do
    Keyword.put(params, :reply_markup, keyboard)
  end
end
