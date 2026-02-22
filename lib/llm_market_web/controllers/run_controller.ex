defmodule LlmMarketWeb.RunController do
  use LlmMarketWeb, :controller

  alias LlmMarket.Repo
  alias LlmMarket.Schemas.Run

  import Ecto.Query

  @doc """
  Show a run by ID.
  """
  def show(conn, %{"id" => id}) do
    case get_run(id) do
      nil ->
        conn
        |> put_status(404)
        |> json(%{error: "Run not found"})

      run ->
        json(conn, format_run(run))
    end
  end

  @doc """
  Replay a run (re-render without re-calling providers).
  """
  def replay(conn, %{"id" => id}) do
    case get_run_with_details(id) do
      nil ->
        conn
        |> put_status(404)
        |> json(%{error: "Run not found"})

      run ->
        json(conn, format_run_replay(run))
    end
  end

  defp get_run(id) do
    Repo.get(Run, id)
  rescue
    Ecto.Query.CastError -> nil
  end

  defp get_run_with_details(id) do
    Run
    |> where([r], r.id == ^id)
    |> preload([:provider_answers, :dredd_output])
    |> Repo.one()
  rescue
    Ecto.Query.CastError -> nil
  end

  defp format_run(run) do
    %{
      id: run.id,
      status: run.status,
      question: run.question,
      rounds_completed: run.rounds_completed,
      convergence_achieved: run.convergence_achieved,
      total_latency_ms: run.total_latency_ms,
      total_cost_usd: run.total_cost_usd,
      created_at: run.inserted_at
    }
  end

  defp format_run_replay(run) do
    %{
      run: format_run(run),
      provider_answers:
        Enum.map(run.provider_answers, fn pa ->
          %{
            round: pa.round,
            provider: pa.provider,
            model: pa.model,
            status: pa.status,
            answer: pa.answer,
            confidence: pa.confidence,
            key_claims: pa.key_claims,
            latency_ms: pa.latency_ms
          }
        end),
      dredd_output:
        if run.dredd_output do
          %{
            final_answer: run.dredd_output.final_answer,
            overall_confidence: run.dredd_output.overall_confidence,
            agreements: run.dredd_output.agreements,
            conflicts: run.dredd_output.conflicts,
            dredd_failed: run.dredd_output.dredd_failed
          }
        else
          nil
        end
    }
  end
end
