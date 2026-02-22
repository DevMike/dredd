defmodule LlmMarket do
  @moduledoc """
  LLM Market Bot - Multi-model consensus through market dynamics.

  This application orchestrates multiple LLM providers (OpenAI, Anthropic, Gemini),
  runs a multi-round "market" where models submit answers with confidence scores,
  then revise after seeing others' responses. A dredd model synthesizes the final consensus.
  """

  @doc """
  Returns the configured providers with their settings.
  """
  def providers do
    Application.get_env(:llm_market, :providers, %{})
  end

  @doc """
  Returns enabled providers (those with valid API keys configured).
  """
  def enabled_providers do
    api_keys = Application.get_env(:llm_market, :api_keys, %{})
    providers = providers()

    providers
    |> Enum.filter(fn {name, config} ->
      config[:enabled] && api_keys[name] != nil && api_keys[name] != ""
    end)
    |> Map.new()
  end

  @doc """
  Returns the market configuration.
  """
  def market_config do
    Application.get_env(:llm_market, :market, %{})
  end

  @doc """
  Returns the bot configuration.
  """
  def bot_config do
    Application.get_env(:llm_market, :bot, %{})
  end

  @doc """
  Returns the dredd (arbiter) configuration.
  """
  def dredd_config do
    Application.get_env(:llm_market, :dredd, %{})
  end

  @doc """
  Returns the Telegram configuration.
  """
  def telegram_config do
    Application.get_env(:llm_market, :telegram, %{})
  end

  @doc """
  Checks if debug mode is enabled.
  """
  def debug_mode? do
    bot_config()[:debug_mode] || false
  end
end
