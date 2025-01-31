defmodule Convoy.Railway do
  require Logger
  # hardcoded ftw
  @project_id "2b31f950-2c62-40c0-ba7e-67b908a08687"
  @environment_id "7758cb1a-b746-41aa-88b6-a85d3a823bf1"

  def get_nodes() do
    case get_service_instances() do
      {:ok, %Neuron.Response{status_code: 200, body: body}} ->
        body
        |> get_in(["data", "environment", "serviceInstances", "edges"])
        |> Enum.filter(fn %{"node" => %{"serviceName" => name}} ->
          String.contains?(name, "convoy")
        end)
        |> Enum.map(& &1["node"])
        |> Map.new(fn node -> {node["id"], node} end)

      {:ok, %Neuron.Response{status_code: status_code, body: body}} ->
        {:error, "Received unexpected status code: #{status_code}, #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Higher order fn used for launching nodes and monitoring their
  status during the launch life cycle.

  TODO: finish doc

  launch node
  ├── service create
  ├── service instance deploy
  ├── get deployment with events
      └── poll until deployment has status SUCCESS or FAILED 
  └── 
  """
  def launch_node(name) do
    case create_service(name) do
      {:ok, %Neuron.Response{status_code: 200, body: body}} ->
        edges = get_in(body, ["data", "serviceCreate", "serviceInstances", "edges"])
        instance = hd(edges)
        service_id = get_in(instance, ["node", "serviceId"])
        Logger.info("got service id!: #{service_id}")

        case service_instance_deploy(service_id) do
          {:ok, %Neuron.Response{status_code: 200, body: body}} ->
            deployment_id = get_in(body, ["data", "serviceInstanceDeployV2"])
            Logger.info("got deployment!: #{deployment_id}")
            start_deployment_watcher(deployment_id)

          {:error, reason} ->
            # TODO: broadcast failure
            Logger.info("failed to deploy service instance: #{inspect(reason)}")
        end

      {:error, reason} ->
        # TODO: broadcast failure 
        Logger.info("failed to create service: #{inspect(reason)}")
    end
  end

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
      query Project($projectId: String!)
        project(id: $projectId) {
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
      """,
      %{"projectId" => @project_id},
      headers: headers()
    )
  end

  def get_service_instances() do
    Neuron.query(
      """
      {
        environment(id: \"#{@environment_id}\") {
          id
          name
          serviceInstances {
              edges {
                  node {
                      id
                      serviceName
                      source {
                          repo
                          image
                      }
                      latestDeployment {
                          deploymentStopped
                          id
                          staticUrl
                          status
                      }
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

  def create_service(name) do
    variables = %{
      "input" => %{
        "source" => %{"repo" => "jackycamp/convoy"},
        "projectId" => @project_id,
        "name" => name,
        "variables" => %{
          "PHX_HOST" => "#{name}-production.up.railway.app",
          "PORT" => "4000",
          "RELEASE_DISTRIBUTION" => "name",
          "RELEASE_NODE" => "#{name}@#{name}.railway.internal",
          "SECRET_KEY_BASE" => "foobar"
        }
      }
    }

    Neuron.query(
      """
      mutation ServiceCreate($input: ServiceCreateInput!) {
        serviceCreate(input: $input) {
          createdAt
          featureFlags
          id
          name
          serviceInstances {
            edges {
              node {
                id
                serviceId
                serviceName
                environmentId
              }
            }
          }
        }
      }
      """,
      variables,
      headers: headers()
    )
  end

  def delete_service(service_id) do
    Neuron.query(
      """
      mutation ServiceDelete($serviceId: String!) {
        serviceDelete(id: $serviceId)
      }
      """,
      %{"serviceId" => service_id},
      headers: headers()
    )
  end

  def service_instance_deploy(service_id) do
    variables = %{
      "environmentId" => @environment_id,
      "serviceId" => service_id
    }

    Neuron.query(
      """
        mutation ServiceInstanceDeployV2($environmentId: String!, $serviceId: String!) {
            serviceInstanceDeployV2(
                environmentId: $environmentId 
                serviceId: $serviceId
            )
        }
      """,
      variables,
      headers: headers()
    )
  end

  def get_deployment(deployment_id) do
    Neuron.query(
      """
      {
        query  Deployment($deploymentId: String!){
            deployment(id: $deploymentId) {
                environmentId
                id
                serviceId
                staticUrl
                status
                updatedAt
                url
                deploymentStopped
            }
          }
      }
      """,
      %{"deploymentId" => deployment_id},
      headers: headers()
    )
  end

  def get_deployment_with_events(deployment_id) do
    Neuron.query(
      """
      query Deployment($deploymentId: String!) {
          deployment(id: $deploymentId) {
              environmentId
              id
              serviceId
              staticUrl
              status
              updatedAt
              url
              deploymentStopped
          }
          deploymentEvents(id: $deploymentId) {
              edges {
                  node {
                      step
                      id
                      createdAt
                      completedAt
                  }
              }
          }
      }
      """,
      %{"deploymentId" => deployment_id},
      headers: headers()
    )
  end

  defp start_deployment_watcher(deployment_id) do
    :timer.sleep(1500)

    Logger.info("deployment watcher, checking status")

    case get_deployment_status(deployment_id) do
      :success ->
        # TODO: broadcast completion
        nil

      :in_progress ->
        # TODO: broadcast last event?
        start_deployment_watcher(deployment_id)

      :failed ->
        # TODO: broadcast failure
        nil
    end
  end

  defp get_deployment_status(deployment_id) do
    case get_deployment_with_events(deployment_id) do
      {:ok, %Neuron.Response{status_code: 200, body: body}} ->
        case get_in(body, ["data", "deployment", "status"]) do
          "SUCCESS" ->
            Logger.info("deployment success!!")
            :success

          "FAILED" ->
            Logger.info("deployment failed. boo")
            :failed

          _ ->
            Logger.info("deployment still in progress")
            :in_progress
        end

      {:error, reason} ->
        Logger.info("failed to get deployment status: #{inspect(reason)}")
        :failed
    end
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
