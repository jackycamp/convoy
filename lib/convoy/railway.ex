defmodule Convoy.Railway do
  # hardcoded ftw
  @project_id "2b31f950-2c62-40c0-ba7e-67b908a08687"
  @environment_id "7758cb1a-b746-41aa-88b6-a85d3a823bf1"

  def me() do
    Neuron.query(
      """
      {
        me {
          email
          id
          name
          riskLevel
          username
        }
      }
      """,
      %{},
      headers: headers()
    )
  end

  def get_services() do
    Neuron.query(
      """
      {
        project(id: \"#{@project_id}\") {
          name
          services {
              edges {
                  node {
                      name
                      id
                  }
              }
          }
        }
      }
      """,
      %{},
      headers: headers()
    )
  end

  def create_service() do
    nil
  end

  def service_instance_deploy() do
    nil
  end

  def get_deployment() do
    nil
  end

  def get_deployment_with_events() do
    nil
  end

  defp headers() do
    token =
      Application.get_env(:convoy, :railway_token) ||
        raise """
        :railway_token not found in Application env vars.
        """

    [authorization: "Bearer #{token}"]
  end
end
