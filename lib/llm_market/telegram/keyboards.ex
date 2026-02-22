defmodule LlmMarket.Telegram.Keyboards do
  @moduledoc """
  Inline keyboard builders for Telegram messages.
  """

  @doc """
  Build the keyboard for run results.
  """
  def run_result_keyboard(run_id) do
    %{
      inline_keyboard: [
        [
          %{text: "Conflicts", callback_data: "conflicts:#{run_id}"},
          %{text: "Raw", callback_data: "raw:#{run_id}"},
          %{text: "Re-run", callback_data: "rerun:#{run_id}"},
          %{text: "Cost/Latency", callback_data: "cost:#{run_id}"}
        ]
      ]
    }
  end
end
