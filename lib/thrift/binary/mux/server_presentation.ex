defmodule Thrift.Binary.Mux.ServerPresentation do
  @behaviour Mux.ServerPresentation

  alias Thrift.Protocol.Binary
  alias Thrift.TApplicationException

  def init(server_module),
    do: {:ok, server_module}

  def decode(iodata, server_module) do
    case Binary.deserialize(:message_begin, iodata) do
      {:ok, {type, seq_id, rpc_name, request_data}} ->
        {request_module, fun_name, response_module} =
          apply(server_module, :__route__, [type, rpc_name])
          request = decode_request(request_module, request_data)
        {:ok, {type, seq_id, rpc_name, response_module}, {fun_name, request}}
    end
  end

  def encode({_, seq_id, rpc_name, _}, %TApplicationException{} = err, _) do
    message = Binary.serialize(:message_begin, {:exception, seq_id, rpc_name})
    err_data = Binary.serialize(:application_exception, err)
    {:ok, [message | err_data]}
  end

  def encode({_, seq_id, rpc_name, response_module}, response, _) do
    message = Binary.serialize(:message_begin, {:reply, seq_id, rpc_name})
    response_data = encode_response(response_module, response)
    {:ok, [message | response_data]}
  end

  def terminate(_, _),
    do: :ok

  defp decode_request(nil, <<0>>),
    do: nil
  defp decode_request(request_module, request_data) do
    {request, ""} = apply(request_module, :deserialize, [request_data])
    request
  end

  defp encode_response(_, nil),
    do: <<0>>
  defp encode_response(response_module, response),
    do: apply(response_module, :serialize, [response])
end
