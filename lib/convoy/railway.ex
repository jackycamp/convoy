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
        |> Map.new(fn node -> {node["serviceName"], Convoy.Node.from_service_instance(node)} end)

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
        Logger.info("instance: #{inspect(instance)}")
        service_id = get_in(instance, ["node", "serviceId"])
        Logger.info("got service id!: #{service_id}")
        Convoy.NodePubsub.broadcast(name, {:load_instance_info, instance["node"]})

        case service_instance_deploy(service_id) do
          {:ok, %Neuron.Response{status_code: 200, body: body}} ->
            deployment_id = get_in(body, ["data", "serviceInstanceDeployV2"])
            Logger.info("got deployment!: #{deployment_id}")
            Convoy.NodePubsub.broadcast(name, {:set_status, "starting deployment"})
            start_deployment_watcher(name, deployment_id)

          {:error, reason} ->
            Logger.info("failed to deploy service instance: #{inspect(reason)}")
            Convoy.NodePubsub.broadcast(name, {:set_status, "FAILED"})
        end

      {:error, reason} ->
        Logger.info("failed to create service: #{inspect(reason)}")
        Convoy.NodePubsub.broadcast(name, {:set_status, "FAILED"})
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
      query Environment($environmentId: String!){
        environment(id: $environmentId) {
          id
          name
          serviceInstances {
              edges {
                  node {
                      id
                      serviceId
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
      %{"environmentId" => @environment_id},
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

  def delete_node(%Convoy.Node{} = node) do
    case delete_service(node.service_id) do
      {:ok, %Neuron.Response{status_code: 200, body: body}} ->
        Phoenix.PubSub.broadcast(Convoy.PubSub, "nodes", {:del_node, node.name})
        Logger.info("deleted node: #{inspect(body)}")

      {:ok, %Neuron.Response{status_code: status_code, body: body}} ->
        Logger.info("got unexpected status code when deleting node: #{status_code}}")
        Logger.info("response body: #{inspect(body)}")
        Convoy.NodePubsub.broadcast(node.name, {:set_status, "failed to delete"})

      {:error, reason} ->
        Logger.info("could not delete node: #{inspect(reason)}")
        Convoy.NodePubsub.broadcast(node.name, {:set_status, "failed to delete"})
    end
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

  defp start_deployment_watcher(name, deployment_id) do
    :timer.sleep(1500)

    Logger.info("deployment watcher, checking status")

    case get_deployment_status(deployment_id) do
      :success ->
        Convoy.NodePubsub.broadcast(name, {:set_status, "SUCCESS"})

      {:in_progress, detail} ->
        Convoy.NodePubsub.broadcast(name, {:set_status, detail})
        start_deployment_watcher(name, deployment_id)

      :failed ->
        Convoy.NodePubsub.broadcast(name, {:set_status, "FAILED"})
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

          in_progress ->
            Logger.info("deployment still in progress: #{in_progress}")
            {:in_progress, in_progress}
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
