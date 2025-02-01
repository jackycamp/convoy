defmodule Convoy.Node do
  defstruct name: "",
            status: "",
            service_id: "",
            service_instance_id: "",
            control_plane?: false

  @type t :: %__MODULE__{
          name: String.t(),
          status: String.t(),
          service_id: String.t(),
          service_instance_id: String.t(),
          control_plane?: boolean()
        }

  def default, do: %__MODULE__{}

  def with_name(name) when is_binary(name), do: %__MODULE__{name: name}

  def set_status(%__MODULE__{} = node, status) when is_binary(status),
    do: %{node | status: status}

  def load_instance_info(%__MODULE__{} = node, inst) when is_map(inst),
    do: %{
      node
      | service_id: Map.get(inst, "serviceId", ""),
        service_instance_id: Map.get(inst, "id", "")
    }

  def from_service_instance(inst) when is_map(inst) do
    name = Map.get(inst, "serviceName", "")
    latest_deploy = Map.get(inst, "latestDeployment", %{})

    %__MODULE__{
      name: name,
      status: Map.get(latest_deploy, "status", ""),
      service_id: Map.get(inst, "serviceId", ""),
      service_instance_id: Map.get(inst, "id", ""),
      control_plane?: name == "convoy"
    }
  end
end
