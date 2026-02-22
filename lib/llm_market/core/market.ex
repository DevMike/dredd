defmodule LlmMarket.Core.Market do
  @moduledoc """
  Market orchestration - the main entry point for running a question
  through the multi-model consensus process.
  """

  require Logger

  alias LlmMarket.Core.{Convergence, Dredd, Prompts}
  alias LlmMarket.Orchestrator.ProviderClient
  alias LlmMarket.Repo
  alias LlmMarket.Schemas.{Thread, Run, ProviderAnswer, DreddOutput}
  alias LlmMarket.Telemetry

  @doc """
  Run a question through the market process.

  1. Create run record
  2. Execute rounds until convergence or max_rounds
  3. Call dredd to synthesize
  4. Persist results
  """
  def run(chat_id, question, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    # Get or create thread
    thread = get_or_create_thread(chat_id)

    # Create run
    {:ok, run} = create_run(thread.id, question)

    Telemetry.run_start(run.id, question)

    # Get config
    max_rounds = opts[:max_rounds] || LlmMarket.market_config()[:max_rounds] || 2
    dredd_config = Thread.get_dredd(thread)

    # Execute market rounds
    case execute_rounds(run.id, question, max_rounds) do
      {:ok, final_responses, rounds_completed, convergence_achieved} ->
        # Call dredd
        case Dredd.run(run.id, question, final_responses, rounds_completed, dredd: dredd_config) do
          {:ok, dredd_output} ->
            finalize_success(run, rounds_completed, convergence_achieved, dredd_output, start_time)

          {:error, :all_dredds_failed, best_response, failed_output} ->
            finalize_dredd_failed(
              run,
              rounds_completed,
              convergence_achieved,
              failed_output,
              best_response,
              start_time
            )
        end

      {:error, :all_providers_failed} ->
        finalize_failed(run, start_time)
    end
  end

  defp execute_rounds(run_id, question, max_rounds) do
    providers = LlmMarket.enabled_providers() |> Map.keys()

    if Enum.empty?(providers) do
      {:error, :all_providers_failed}
    else
      do_rounds(run_id, question, providers, max_rounds, 1, nil)
    end
  end

  defp do_rounds(run_id, question, providers, max_rounds, round, previous_responses) do
    round_start = System.monotonic_time(:millisecond)

    # Generate prompts
    prompts = generate_prompts(question, round, previous_responses, providers)

    # Fan out to providers
    responses = fan_out(providers, prompts, run_id, round)

    # Check if we got any successful responses
    successful =
      responses
      |> Enum.filter(fn {_provider, _model, response} ->
        response[:status] in ["ok", "parse_error", :ok, :parse_error]
      end)

    if Enum.empty?(successful) do
      {:error, :all_providers_failed}
    else
      round_duration = System.monotonic_time(:millisecond) - round_start
      Telemetry.run_round_complete(run_id, round, length(successful), round_duration)

      # Check convergence
      config = LlmMarket.market_config()

      {converged, _metrics} =
        Convergence.check(successful,
          confidence_threshold: config[:convergence_confidence_threshold],
          overlap_threshold: config[:convergence_claim_overlap]
        )

      cond do
        # Reached max rounds
        round >= max_rounds ->
          {:ok, successful, round, converged}

        # Converged
        converged ->
          {:ok, successful, round, true}

        # Continue to next round
        true ->
          do_rounds(run_id, question, providers, max_rounds, round + 1, successful)
      end
    end
  end

  defp generate_prompts(question, 1, _previous, _providers) do
    prompt = Prompts.round_1(question)
    # Same prompt for all providers in round 1
    fn _provider -> prompt end
  end

  defp generate_prompts(question, _round, previous_responses, _providers) do
    # Build provider-specific prompts for round 2+
    disagreements = Convergence.detect_disagreements(previous_responses)

    fn provider ->
      own_response = find_response(previous_responses, provider)
      others = Enum.reject(previous_responses, fn {p, _, _} -> p == provider end)

      if own_response do
        Prompts.round_2(question, own_response, others, disagreements)
      else
        # Provider failed in previous round, give them round 1 prompt
        Prompts.round_1(question)
      end
    end
  end

  defp find_response(responses, provider) do
    case Enum.find(responses, fn {p, _, _} -> p == provider end) do
      {_, _, response} -> response
      nil -> nil
    end
  end

  defp fan_out(providers, prompt_fn, run_id, round) do
    config = LlmMarket.market_config()
    concurrency = config[:max_concurrency] || 4

    Task.Supervisor.async_stream(
      LlmMarket.Orchestrator.TaskSupervisor,
      providers,
      fn provider ->
        prompt = prompt_fn.(provider)
        call_provider(provider, prompt, run_id, round)
      end,
      max_concurrency: concurrency,
      timeout: (config[:provider_timeout_ms] || 25_000) + 5_000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, _reason} -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp call_provider(provider, prompt, run_id, round) do
    provider_config = LlmMarket.providers()[provider] || %{}
    model = provider_config[:default_model]

    Telemetry.provider_call_start(provider, model, run_id)

    result = ProviderClient.call(provider, prompt)

    case result do
      {:ok, normalized} ->
        Telemetry.provider_call_stop(
          provider,
          model,
          run_id,
          normalized[:latency_ms],
          normalized[:status],
          normalized[:usage][:total_tokens],
          normalized[:usage][:cost_usd]
        )

        # Persist the answer
        persist_answer(run_id, round, provider, normalized)

        {provider, normalized[:model] || model, normalized}

      {:error, error} ->
        Telemetry.provider_call_exception(provider, model, run_id, :error, error)

        # Persist the error
        error_normalized = %{
          status: error[:type] |> to_string(),
          error: error,
          latency_ms: error[:latency_ms]
        }

        persist_answer(run_id, round, provider, error_normalized)

        {provider, model, error_normalized}
    end
  end

  defp persist_answer(run_id, round, provider, normalized) do
    attrs = ProviderAnswer.from_normalized(run_id, round, provider, normalized)

    %ProviderAnswer{}
    |> ProviderAnswer.changeset(attrs)
    |> Repo.insert()
  end

  defp finalize_success(run, rounds_completed, convergence_achieved, dredd_output, start_time) do
    total_latency = System.monotonic_time(:millisecond) - start_time

    # Calculate total cost
    total_cost = calculate_total_cost(run.id, dredd_output[:cost_usd])

    # Persist dredd output
    {:ok, _} =
      %DreddOutput{}
      |> DreddOutput.changeset(dredd_output)
      |> Repo.insert()

    # Update run
    {:ok, run} =
      run
      |> Run.complete_changeset(%{
        status: "completed",
        rounds_completed: rounds_completed,
        convergence_achieved: convergence_achieved,
        total_latency_ms: total_latency,
        total_cost_usd: total_cost
      })
      |> Repo.update()

    Telemetry.run_complete(run.id, total_latency, total_cost)

    # Reload with associations
    run = Repo.preload(run, [:dredd_output, :provider_answers])
    {:ok, run}
  end

  defp finalize_dredd_failed(
         run,
         rounds_completed,
         convergence_achieved,
         failed_output,
         _best_response,
         start_time
       ) do
    total_latency = System.monotonic_time(:millisecond) - start_time
    total_cost = calculate_total_cost(run.id, nil)

    # Persist failed dredd output
    {:ok, _} =
      %DreddOutput{}
      |> DreddOutput.changeset(failed_output)
      |> Repo.insert()

    # Update run
    {:ok, run} =
      run
      |> Run.complete_changeset(%{
        status: "completed",
        rounds_completed: rounds_completed,
        convergence_achieved: convergence_achieved,
        total_latency_ms: total_latency,
        total_cost_usd: total_cost
      })
      |> Repo.update()

    run = Repo.preload(run, [:dredd_output, :provider_answers])
    {:ok, run}
  end

  defp finalize_failed(run, start_time) do
    total_latency = System.monotonic_time(:millisecond) - start_time

    {:ok, _run} =
      run
      |> Run.complete_changeset(%{
        status: "failed",
        total_latency_ms: total_latency
      })
      |> Repo.update()

    Telemetry.run_failed(run.id, :all_providers_failed)

    {:error, :all_providers_failed}
  end

  defp calculate_total_cost(run_id, dredd_cost) do
    import Ecto.Query

    provider_costs =
      ProviderAnswer
      |> where([pa], pa.run_id == ^run_id)
      |> select([pa], pa.usage)
      |> Repo.all()
      |> Enum.map(fn usage ->
        (usage || %{})["cost_usd"] || 0
      end)
      |> Enum.sum()

    provider_costs + (dredd_cost || 0)
  end

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

  defp create_run(thread_id, question) do
    %Run{}
    |> Run.changeset(%{
      thread_id: thread_id,
      question: question,
      status: "in_progress"
    })
    |> Repo.insert()
  end
end
