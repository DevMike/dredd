defmodule LlmMarket.Telegram.Commands do
  @moduledoc """
  Command handlers for the Telegram bot.
  """

  require Logger

  alias LlmMarket.Telegram.{Bot, Formatter, Keyboards, PendingPrompts}
  alias LlmMarket.Core.{Market, PromptRefiner}
  alias LlmMarket.Repo
  alias LlmMarket.Schemas.{Thread, Run}

  import Ecto.Query

  @doc """
  Handle /ask command - start a new run with prompt refinement.
  """
  def handle_ask(chat_id, question) do
    max_length = LlmMarket.bot_config()[:max_question_length] || 4000

    cond do
      String.length(question) == 0 ->
        Bot.send_message(chat_id, "Please provide a question. Usage: `/ask <your question>`")

      String.length(question) > max_length ->
        Bot.send_message(
          chat_id,
          "Question too long. Maximum length is #{max_length} characters."
        )

      true ->
        # Try to refine the prompt
        case PromptRefiner.refine(question) do
          {:ok, suggested} when suggested != question ->
            # Show suggestion with buttons
            message = format_suggestion(suggested)
            keyboard = Keyboards.prompt_refinement_keyboard(chat_id)

            case Bot.send_message(chat_id, message, reply_markup: keyboard) do
              {:ok, sent_message} ->
                PendingPrompts.store(chat_id, question, suggested, sent_message.message_id)

              _ ->
                # Fallback: proceed with original
                run_market(chat_id, question)
            end

          _ ->
            # Refinement failed or same as original, proceed directly
            run_market(chat_id, question)
        end
    end
  end

  @doc """
  Handle /ask! command - skip refinement and run directly.
  """
  def handle_ask_direct(chat_id, question) do
    max_length = LlmMarket.bot_config()[:max_question_length] || 4000

    cond do
      String.length(question) == 0 ->
        Bot.send_message(chat_id, "Please provide a question. Usage: `/ask! <your question>`")

      String.length(question) > max_length ->
        Bot.send_message(
          chat_id,
          "Question too long. Maximum length is #{max_length} characters."
        )

      true ->
        run_market(chat_id, question)
    end
  end

  defp format_suggestion(suggested) do
    """
    📝 Suggested prompt:

    "#{suggested}"

    Or reply to this message with your edited version.
    """
  end

  defp run_market(chat_id, question) do
    Bot.send_message(chat_id, "Processing your question...")

    Task.start(fn ->
      case Market.run(chat_id, question) do
        {:ok, run} ->
          response = Formatter.format_run_result(run)
          keyboard = Keyboards.run_result_keyboard(run.id)
          Bot.send_message(chat_id, response, reply_markup: keyboard)

        {:error, reason} ->
          Bot.send_message(chat_id, Formatter.format_error(reason))
      end
    end)
  end

  @doc """
  Handle /last command - show last run.
  """
  def handle_last(chat_id) do
    thread = get_or_create_thread(chat_id)

    case get_last_run(thread.id) do
      nil ->
        Bot.send_message(chat_id, "No previous runs found. Use `/ask <question>` to start one.")

      run ->
        response = Formatter.format_run_result(run)
        keyboard = Keyboards.run_result_keyboard(run.id)
        Bot.send_message(chat_id, response, reply_markup: keyboard)
    end
  end

  @doc """
  Handle /run command - show a specific run.
  """
  def handle_run(chat_id, run_id) do
    case get_run(run_id) do
      nil ->
        Bot.send_message(chat_id, "Run not found.")

      run ->
        response = Formatter.format_run_result(run)
        keyboard = Keyboards.run_result_keyboard(run.id)
        Bot.send_message(chat_id, response, reply_markup: keyboard)
    end
  end

  @doc """
  Handle /raw command - show raw provider answers.
  """
  def handle_raw(chat_id, run_id) do
    case get_run_with_answers(run_id) do
      nil ->
        Bot.send_message(chat_id, "Run not found.")

      run ->
        messages = Formatter.format_raw_answers(run)
        # Send each message with a small delay to maintain order
        Enum.each(messages, fn msg ->
          Bot.send_message(chat_id, msg)
          Process.sleep(100)
        end)
    end
  end

  @doc """
  Handle /conflicts command - show conflicts.
  """
  def handle_conflicts(chat_id, run_id) do
    case get_run_with_dredd(run_id) do
      nil ->
        Bot.send_message(chat_id, "Run not found.")

      run ->
        response = Formatter.format_conflicts(run)
        Bot.send_message(chat_id, response)
    end
  end

  @doc """
  Handle /dredd command - set default dredd.
  """
  def handle_dredd(chat_id, dredd_spec) do
    case parse_dredd_spec(dredd_spec) do
      {:ok, provider, model} ->
        thread = get_or_create_thread(chat_id)
        update_thread_dredd(thread, provider, model)

        Bot.send_message(
          chat_id,
          "Default dredd set to `#{provider}:#{model}`"
        )

      :error ->
        Bot.send_message(
          chat_id,
          "Invalid format. Usage: `/dredd provider:model`\n" <>
            "Example: `/dredd anthropic:claude-sonnet-4-20250514`"
        )
    end
  end

  @doc """
  Handle /providers command - list enabled providers.
  """
  def handle_providers(chat_id) do
    providers = LlmMarket.enabled_providers()
    response = Formatter.format_providers(providers)
    Bot.send_message(chat_id, response)
  end

  @doc """
  Handle /config command - show current settings.
  """
  def handle_config(chat_id) do
    thread = get_or_create_thread(chat_id)
    response = Formatter.format_config(thread)
    Bot.send_message(chat_id, response)
  end

  @doc """
  Handle /cancel command - cancel running request.
  """
  def handle_cancel(chat_id) do
    # TODO: Implement run cancellation
    Bot.send_message(chat_id, "No running request to cancel.")
  end

  @doc """
  Handle /status command - show current status.
  """
  def handle_status(chat_id) do
    # TODO: Check for in-progress runs
    Bot.send_message(chat_id, "No request currently in progress.")
  end

  @doc """
  Handle /help command.
  """
  def handle_help(chat_id) do
    help_text = """
    *LLM Market Bot*

    I orchestrate multiple AI models to find consensus on your questions.

    *Commands:*
    `/ask <question>` - Ask a question (with prompt refinement)
    `/ask! <question>` - Ask without refinement
    `/last` - Show last run result
    `/run <id>` - Show a specific run
    `/raw <id>` - Show raw provider answers
    `/conflicts <id>` - Show conflicts
    `/dredd <provider:model>` - Set default dredd
    `/providers` - List enabled providers
    `/config` - Show current settings
    `/cancel` - Cancel running request
    `/status` - Show current status
    `/help` - Show this message
    """

    Bot.send_message(chat_id, help_text)
  end

  @doc """
  Handle rerun callback.
  """
  def handle_rerun(chat_id, run_id) do
    case get_run(run_id) do
      nil ->
        Bot.send_message(chat_id, "Run not found.")

      run ->
        handle_ask(chat_id, run.question)
    end
  end

  @doc """
  Handle cost callback.
  """
  def handle_cost(chat_id, run_id) do
    case get_run_with_answers(run_id) do
      nil ->
        Bot.send_message(chat_id, "Run not found.")

      run ->
        response = Formatter.format_cost_breakdown(run)
        Bot.send_message(chat_id, response)
    end
  end

  @doc """
  Handle "Use Suggested" callback.
  """
  def handle_use_suggested(chat_id) do
    case PendingPrompts.pop(chat_id) do
      {:ok, %{suggested: suggested}} ->
        run_market(chat_id, suggested)

      :not_found ->
        Bot.send_message(chat_id, "No pending suggestion found. Use /ask to start.")
    end
  end

  @doc """
  Handle "Use Original" callback.
  """
  def handle_use_original(chat_id) do
    case PendingPrompts.pop(chat_id) do
      {:ok, %{original: original}} ->
        run_market(chat_id, original)

      :not_found ->
        Bot.send_message(chat_id, "No pending suggestion found. Use /ask to start.")
    end
  end

  @doc """
  Handle reply to a pending prompt message.
  Returns :handled if it was a reply to a pending prompt, :ignore otherwise.
  """
  def handle_reply_edit(chat_id, edited_text, reply_to_message_id) do
    case PendingPrompts.get_by_message_id(reply_to_message_id) do
      {:ok, ^chat_id, _data} ->
        PendingPrompts.pop(chat_id)
        run_market(chat_id, edited_text)
        :handled

      _ ->
        :ignore
    end
  end

  # Private helpers

  defp get_or_create_thread(chat_id) do
    case Repo.get_by(Thread, telegram_chat_id: chat_id) do
      nil ->
        {:ok, thread} =
          %Thread{}
          |> Thread.changeset(%{telegram_chat_id: chat_id})
          |> Repo.insert()

        thread

      thread ->
        thread
    end
  end

  defp get_last_run(thread_id) do
    Run
    |> where([r], r.thread_id == ^thread_id)
    |> order_by([r], desc: r.inserted_at)
    |> limit(1)
    |> preload([:dredd_output])
    |> Repo.one()
  end

  defp get_run(run_id) do
    Run
    |> preload([:dredd_output])
    |> Repo.get(run_id)
  rescue
    Ecto.Query.CastError -> nil
  end

  defp get_run_with_answers(run_id) do
    Run
    |> preload([:provider_answers, :dredd_output])
    |> Repo.get(run_id)
  rescue
    Ecto.Query.CastError -> nil
  end

  defp get_run_with_dredd(run_id) do
    Run
    |> preload([:dredd_output])
    |> Repo.get(run_id)
  rescue
    Ecto.Query.CastError -> nil
  end

  defp update_thread_dredd(thread, provider, model) do
    thread
    |> Thread.changeset(%{
      default_dredd_provider: to_string(provider),
      default_dredd_model: model
    })
    |> Repo.update()
  end

  defp parse_dredd_spec(spec) do
    case String.split(spec, ":") do
      [provider, model] when byte_size(provider) > 0 and byte_size(model) > 0 ->
        {:ok, String.to_atom(provider), model}

      _ ->
        :error
    end
  end
end
