defmodule LlmMarket.Providers.Behaviour do
  @moduledoc """
  Behaviour definition for LLM provider adapters.

  All providers must implement these callbacks to ensure consistent
  interface across different LLM APIs.
  """

  @typedoc """
  Raw response from the provider API.
  """
  @type raw_response :: map()

  @typedoc """
  Normalized answer matching our canonical schema.
  """
  @type normalized_answer :: %{
          optional(:model) => String.t(),
          optional(:status) => String.t(),
          optional(:answer) => String.t(),
          optional(:confidence) => float() | nil,
          optional(:key_claims) => [String.t()] | nil,
          optional(:assumptions) => [String.t()] | nil,
          optional(:citations) => [map()] | nil,
          optional(:usage) => map() | nil,
          optional(:latency_ms) => integer(),
          optional(:error) => map() | nil,
          optional(:raw_response) => String.t() | nil
        }

  @typedoc """
  Error response.
  """
  @type error :: %{
          type: atom(),
          message: String.t(),
          http_status: integer() | nil
        }

  @doc """
  Make a call to the provider's API.

  ## Options
  - `:model` - The model to use (defaults to provider's default)
  - `:timeout` - Request timeout in milliseconds
  - `:temperature` - Sampling temperature (0.0-2.0)
  """
  @callback call(prompt :: String.t(), opts :: keyword()) ::
              {:ok, raw_response()} | {:error, error()}

  @doc """
  Normalize a raw API response into our canonical schema.
  """
  @callback normalize(raw_response()) :: normalized_answer()

  @doc """
  Estimate cost based on usage data and model.
  Returns nil if cost cannot be estimated.
  """
  @callback estimate_cost(usage :: map(), model :: String.t()) :: float() | nil
end
