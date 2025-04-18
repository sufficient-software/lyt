defmodule PhxAnalytics do
  @moduledoc """
  Documentation for `PhxAnalytics`.
  """

  alias PhxAnalytics.{Session, Event, Repo}

  def create_session(attrs \\ %{}) do
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert!(
      # without `returning: true`, it will optimistically return the data from the changeset
      # instead of the real values from the database
      returning: true,
      conflict_target: :id,
      on_conflict: {:replace, Session.upsert_keys()}
    )
  end

  def create_event(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert!()
  end

  def parse_user_agent(user_agent) do
    case UAInspector.parse(user_agent) do
      %UAInspector.Result{
        client: %{name: client_name, version: client_version},
        os: %{name: os_name, version: os_version}
      } ->
        %{
          browser: client_name,
          browser_version: client_version,
          operating_system: os_name,
          operating_system_version: os_version
        }

      %UAInspector.Result.Bot{name: name} ->
        %{
          browser: name
        }

      _ ->
        %{browser: "Unknown"}
    end
  end

  def parse_utm(params \\ %{}) do
    %{
      utm_source: Map.get(params, "utm_source"),
      utm_medium: Map.get(params, "utm_medium"),
      utm_campaign: Map.get(params, "utm_campaign"),
      utm_term: Map.get(params, "utm_term"),
      utm_content: Map.get(params, "utm_content")
    }
  end

  def generate_session_id() do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
