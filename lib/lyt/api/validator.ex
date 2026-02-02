defmodule Lyt.API.Validator do
  @moduledoc """
  Request validation for the Lyt API.
  """

  @default_max_batch_size 100
  @default_max_metadata_size 10_240
  @default_max_name_length 255
  @max_path_length 2048

  @doc """
  Validate a single event request.

  Required fields:
  - `name` - non-empty string

  Optional fields:
  - `path` - string, max 2048 chars
  - `hostname` - string
  - `metadata` - map, max 10KB
  """
  def validate_event(params) do
    errors =
      []
      |> validate_required_string(params, "name", max_name_length())
      |> validate_optional_string(params, "path", @max_path_length)
      |> validate_optional_metadata(params)

    case errors do
      [] -> {:ok, params}
      _ -> {:error, {:validation, Enum.reverse(errors)}}
    end
  end

  @doc """
  Validate a batch events request.

  Required:
  - `events` - non-empty array of events

  Each event is validated with `validate_event/1`.
  """
  def validate_batch(params) do
    events = params["events"]

    cond do
      !is_list(events) ->
        {:error, {:validation, [{:events, "must be an array"}]}}

      length(events) == 0 ->
        {:error, {:validation, [{:events, "cannot be empty"}]}}

      length(events) > max_batch_size() ->
        {:error, {:validation, [{:events, "exceeds maximum batch size (#{max_batch_size()})"}]}}

      true ->
        validate_each_event(events)
    end
  end

  defp validate_each_event(events) do
    results =
      events
      |> Enum.with_index()
      |> Enum.map(fn {event, idx} ->
        case validate_event(event) do
          {:ok, _} -> :ok
          {:error, {:validation, errs}} -> {:error, idx, errs}
        end
      end)

    errors = Enum.filter(results, &match?({:error, _, _}, &1))

    if errors == [] do
      {:ok, events}
    else
      formatted =
        Enum.flat_map(errors, fn {:error, idx, errs} ->
          Enum.map(errs, fn {field, msg} ->
            {:"events[#{idx}].#{field}", msg}
          end)
        end)

      {:error, {:validation, formatted}}
    end
  end

  defp validate_required_string(errors, params, field, max_length) do
    value = params[field]

    cond do
      is_nil(value) or value == "" ->
        [{String.to_atom(field), "is required"} | errors]

      not is_binary(value) ->
        [{String.to_atom(field), "must be a string"} | errors]

      String.length(value) > max_length ->
        [{String.to_atom(field), "exceeds maximum length (#{max_length})"} | errors]

      true ->
        errors
    end
  end

  defp validate_optional_string(errors, params, field, max_length) do
    value = params[field]

    cond do
      is_nil(value) ->
        errors

      not is_binary(value) ->
        [{String.to_atom(field), "must be a string"} | errors]

      String.length(value) > max_length ->
        [{String.to_atom(field), "exceeds maximum length (#{max_length})"} | errors]

      true ->
        errors
    end
  end

  defp validate_optional_metadata(errors, params) do
    metadata = params["metadata"]

    cond do
      is_nil(metadata) ->
        errors

      not is_map(metadata) ->
        [{:metadata, "must be an object"} | errors]

      metadata_too_large?(metadata) ->
        [{:metadata, "exceeds maximum size (#{max_metadata_size()} bytes)"} | errors]

      true ->
        errors
    end
  end

  defp metadata_too_large?(metadata) do
    byte_size(Jason.encode!(metadata)) > max_metadata_size()
  rescue
    _ -> true
  end

  defp max_batch_size do
    get_config(:max_batch_size, @default_max_batch_size)
  end

  defp max_metadata_size do
    get_config(:max_metadata_size, @default_max_metadata_size)
  end

  defp max_name_length do
    get_config(:max_name_length, @default_max_name_length)
  end

  defp get_config(key, default) do
    Application.get_env(:lyt, Lyt.API.Router, [])
    |> Keyword.get(key, default)
  end
end
