defmodule LlmMarket.Telegram.PendingPrompts do
  @moduledoc """
  ETS-based storage for pending prompt refinements.

  Stores pending prompts keyed by chat_id, allowing retrieval by
  either chat_id or message_id.
  """

  use GenServer

  @table :pending_prompts

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Store a pending prompt refinement.
  """
  def store(chat_id, original, suggested, message_id) do
    :ets.insert(@table, {chat_id, %{
      original: original,
      suggested: suggested,
      message_id: message_id,
      created_at: System.system_time(:second)
    }})
    :ok
  end

  @doc """
  Get and remove a pending prompt by chat_id.
  """
  def pop(chat_id) do
    case :ets.take(@table, chat_id) do
      [{^chat_id, data}] -> {:ok, data}
      [] -> :not_found
    end
  end

  @doc """
  Get a pending prompt by message_id.
  Returns {:ok, chat_id, data} or :not_found.
  """
  def get_by_message_id(message_id) do
    # Match any entry where message_id matches
    case :ets.match_object(@table, {:_, %{message_id: message_id}}) do
      [{chat_id, data}] -> {:ok, chat_id, data}
      [] -> :not_found
    end
  end

  # GenServer callbacks

  @impl true
  def init(_) do
    table = :ets.new(@table, [:set, :public, :named_table])
    {:ok, table}
  end
end
