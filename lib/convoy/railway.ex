defmodule Convoy.Railway do
  @moduledoc """
  A module that lets you interact with a Railway environment.
  Spin up nodes, monitor their deployment, and spin them down.

  Note, this module is currently hard-coded to support my railway 
  project/environment, could be easily changed.

  Several functions are simply wrappers around graphql queries
  that return:

    {:ok, %Neuron.Response{status_code: status_code, body: body}}
    {:error, reason}

  Check out the specific function's doc to see what the
  body of the response looks like. Generally, this will be a `map`
  in accordance with the structure of the query.
  """

  require Logger
  # like i said, hardcoded
  @project_id "2b31f950-2c62-40c0-ba7e-67b908a08687"
  @environment_id "7758cb1a-b746-41aa-88b6-a85d3a823bf1"

  @doc """
  Retrieves running nodes in the environment.
  Returns a map where keys are node names 
  and the values are `Convoy.Node` named structs.

  ## Examples
    
      iex> Convoy.Railway.get_nodes()
      %{"convoy-jdsk": %Convoy.Node{id: "convoy-jdsk", status: "SUCCESS" ...} }
  """
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
  Give a name, launch a node in railway's environment.
  Manages and broadcasts updates during the entire launch
  cycle to the corresponding node channel topic.

  Below outlines the flow for launching a node.

  launch node
  ├── create railway service
  ├── deploy the service instance
  ├── deployment watcher
  │     └── let railway build image, and take care of deployment
  │     └── poll every 1.5s until deployment has status SUCCESS or FAILED 
  │     └── broadcast to node channel informing status
  └── node shell ready

  This function doesn't return anything, it's intended to run
  "in the background" and broadcast status messages.

  ## Examples

    iex> Convoy.Railway.launch_node("convoy-jdsk")
  """
  def launch_node(name) do
    case create_service(name) do
      {:ok, %Neuron.Response{status_code: 200, body: body}} ->
        edges = get_in(body, ["data", "serviceCreate", "serviceInstances", "edges"])
        instance = hd(edges)
        service_id = get_in(instance, ["node", "serviceId"])
        Convoy.NodePubsub.broadcast(name, {:load_instance_info, instance["node"]})

        case service_instance_deploy(service_id) do
          {:ok, %Neuron.Response{status_code: 200, body: body}} ->
            deployment_id = get_in(body, ["data", "serviceInstanceDeployV2"])
            Convoy.NodePubsub.broadcast(name, {:set_status, "starting deployment"})
            start_deployment_watcher(name, deployment_id)

          {:error, reason} ->
            Logger.warning("failed to deploy service instance: #{inspect(reason)}")
            Convoy.NodePubsub.broadcast(name, {:set_status, "FAILED"})
        end

      {:error, reason} ->
        Logger.warning("failed to create service: #{inspect(reason)}")
        Convoy.NodePubsub.broadcast(name, {:set_status, "FAILED"})
    end
  end

  @doc """
  Get your user account. Helpful for checking that
  auth and queries are working properly.

  ## Examples

    iex> Railway.me()
  """
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

  @doc """
  Retrieve the services in a project.

  ## Examples

    iex> Railway.get_services()
  """
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

  @doc """
  Retrieve the service instances in a project.

  ## Examples

    iex> Railway.get_service_instances()
    %{"data" => 
      %{"environment" => 
        %{
          "id" => "..",
          "name" => "..",
          "serviceInstances" => %{
            "edges" => [
              %{"node" => %{
                "id" => "..",
                "serviceId" => "..",
                "serviceName" => "..",
                "source" => %{
                  "repo" => "..", 
                  "image" => "..", 
                  },
                "latestDeployment" => %{
                  "deploymentStopped" => "..", 
                  "id" => "..", 
                  "status" => "..", 
                  },
                }
              }
            ]
          },
         }
        }
      }
  """
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

  @doc """
  Given a name for a node, creates the convoy service
  for that node in our railway environment.

  Right now, it's pretty coupled to the convoy
  source repo/convoy elixir app. But some cut points
  could be made to make it more generalized :)

  ## Examples

    iex> Railway.create_service("convoy-jdsk")
    %{"data" => 
      %{"serviceCreate" => 
        %{
          "createdAt" => "..",
          "id" => "..",
          "name" => "..",
          "featureFlags" => "..",
          "serviceInstances" => %{
            "edges" => [
              %{"node" => %{
                "id" => "..",
                "serviceId" => "..",
                "serviceName" => "..",
                "environmentId" => "..",
                }
              }
            ]
          },
         }
        }
      }
  """
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
          # "RELEASE_NODE" => "#{name}@#{name}.railway.internal",
          # "RELEASE_NODE" => "#{name}@convoy.railway.internal",
          "RELEASE_NODE" => "convoy@#{name}.railway.internal",
          "SECRET_KEY_BASE" => "#{gen_secret_key()}",
          "RAILWAY_API_URL" => "#{Application.get_env(:convoy, :railway_url)}",
          "RAILWAY_TOKEN" => "#{Application.get_env(:convoy, :railway_token)}",
          "ECTO_IPV6" => "true",
          "RELEASE_COOKIE" => "super-secret-cookie",
          "ERL_AFLAGS" =>
            "-proto_dist inet6_tcp -kernel inet_dist_listen_min 4444 inet_dist_listen_max 4444"
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

  @doc """
  Deletes a node. Expects a `%Convoy.Node{}` struct
  as an argument. Broadcasts messages on the status
  of deletion.

  ## Examples

    iex> Railway.delete_node(%Convoy.Node{service_id: "6af5511d-ee03-.."})
  """
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

  @doc """
  Deletes a service.

  ## Examples

    iex> Railway.delete_service("6af5511d-ee03-..")
  """
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

  @doc """
  Deploys a service instance given a service id. 
  Retuns a deployment id.

  ## Examples

    iex> Railway.service_instance_deploy(""6af5511d-ee03-.."")
    %{"data" => %{"serviceInstanceDeployV2" => "<deployment_id>"}}
  """
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

  @doc """
  Retrieves a deployment.

  ## Examples

    iex> Railway.get_deployment(""6af5511d-ee03-.."")
    %{"data" => 
      %{"deployment" => 
        %{
          "environmentId" => "..",
          "id" => "..",
          "serviceId" => "..",
          "status" => "..",
          "deploymentStopped" => "..",
         }
        }
      }
  """
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

  @doc """
  Retrieves a deployment with events.

  ## Examples

    iex> Railway.get_deployment_with_events(""6af5511d-ee03-.."")
    %{"data" => 
      %{"deployment" => 
        %{
          "environmentId" => "..",
          "id" => "..",
          "serviceId" => "..",
          "status" => "..",
          "deploymentStopped" => "..",
         }
        },
      %{"deploymentEvents" => %{
          "edges" => [
            %{
              "node" => %{
                "step" => "..",
                "id" => "..",
                "createdAt" => "..",
                "completedAt" => "..",
              }
            }
          ]
      }}
      }
  """
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

  # monitors a deployment, intended to run as a background process
  # broadcasts messages to the node's specific channel accordingly.
  defp start_deployment_watcher(name, deployment_id) do
    :timer.sleep(1500)

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

  # retrieves the status of a deployment
  # primarily used by start_deployment_watcher/2 to repeatedly
  # poll the status of a deployment
  defp get_deployment_status(deployment_id) do
    case get_deployment_with_events(deployment_id) do
      {:ok, %Neuron.Response{status_code: 200, body: body}} ->
        case get_in(body, ["data", "deployment", "status"]) do
          "SUCCESS" ->
            :success

          "FAILED" ->
            :failed

          in_progress ->
            {:in_progress, in_progress}
        end

      {:error, reason} ->
        Logger.info("failed to get deployment status: #{inspect(reason)}")
        :failed
    end
  end

  # returns the headers needed for railway
  # graphql api requests.
  defp headers() do
    token =
      Application.get_env(:convoy, :railway_token) ||
        raise """
        :railway_token not found in Application env vars.
        """

    [authorization: "Bearer #{token}"]
  end

  defp gen_secret_key do
    # in a deployed environment, SECRET_KEY_BASE
    # must exist for all nodes. These do not need to be the same
    # among nodes in the cluster tho. So we just generate a random one each time.
    # Must be at least 64 bytes.
    64
    |> :crypto.strong_rand_bytes()
    |> Base.encode64(padding: false)
  end
end
