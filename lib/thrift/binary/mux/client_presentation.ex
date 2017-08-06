defmodule Thrift.Binary.Mux.ClientPresentation do
  @behaviour Mux.ClientPresentation

  alias Thrift.Protocol.Binary

  def init(state),
    do: {:ok, state}

  def encode({type, rpc_name, request, request_module, response_module}, _) do
    seq_id = System.unique_integer([:positive])
    message = Binary.serialize(:message_begin, {type, seq_id, rpc_name})
    request_data = apply(request_module, :serialize, [request])
    {:ok, {type, seq_id, rpc_name, response_module}, [message | request_data]}
  end

  def decode({type, seq_id, rpc_name, response_module}, iodata, _) do
    case Binary.deserialize(:message_begin, iodata) do
      {:ok, {:reply, ^seq_id, ^rpc_name, response_data}} ->
        decode_response(type, response_module, response_data)
      {:ok, {:exception, ^seq_id, ^rpc_name, err_data}} ->
        {:error, Binary.deserialize(:application_exception, err_data)}
    end
  end

  def terminate(_, _),
    do: :ok

  defp decode_response(:oneway, _, <<0>>),
    do: {:ok, nil}
  defp decode_response(:call, response_module, iodata) do
    case apply(response_module, :deserialize, [iodata]) do
      {%{success: nil} = response, ""} ->
        parse_no_return(response)
      {%{success: success}, ""} ->
        {:ok, success}
    end
  end

  defp parse_no_return(response) do
    case find_exception(response) do
      nil ->
        {:ok, nil}
      exception ->
        {:error, exception}
    end
  end

  defp find_exception(response) do
    response
    |> Map.from_struct()
    |> Map.values()
    |> Enum.find_value(&(&1)) # returns first non-nil value (exception) or nil
  end
end
