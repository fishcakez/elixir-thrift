defmodule Thrift.Generator.Binary.Mux.Client do
  @moduledoc false

  alias Thrift.Generator.{Service, Utils}

  def generate(service_module, service) do
    functions = service.functions
    |> Map.values
    |> Enum.map(&generate_handler_function(service_module, &1))
    |> Utils.merge_blocks


    quote do
      defmodule Binary.Mux.Client do
        @moduledoc false

        def start_link(dest, host, port, opts \\ []) do
          present = {Thrift.Binary.Mux.ClientPresentation, nil}
          addr = String.to_charlist(host)
          opts = [presentation: present, address: addr, port: port] ++ opts
          Mux.Client.start_link(dest, opts)
        end
        unquote_splicing(functions)
      end
    end
  end

  defp generate_handler_function(service_module, function) do
    args_module = service_module
    |> Module.concat(Service.module_name(function, :args))

    response_module = Service.module_name(function, :response)

    underscored_name = function.name
    |> Atom.to_string
    |> Macro.underscore
    |> String.to_atom

    underscored_options_name = :"#{underscored_name}_with_options"
    bang_name = :"#{underscored_name}!"
    options_bang_name = :"#{underscored_options_name}!"

    vars = function.params
    |> Enum.map(&Macro.var(&1.name, nil))

    assignments = function.params
    |> Enum.zip(vars)
    |> Enum.map(fn {param, var} ->
      quote do
        {unquote(param.name), unquote(var)}
      end
    end)

    rpc_name = Atom.to_string(function.name)

    {msg_type, def_type} = if function.oneway do
      {:oneway, quote do: defp}
    else
      {:call, quote do: def}
    end

    quote do
      unquote(def_type)(unquote(underscored_options_name)(dest, unquote_splicing(vars), opts)) do
        args = %unquote(args_module){unquote_splicing(assignments)}
        serialize_module = unquote(Module.concat(args_module, "BinaryProtocol"))
        deserialize_module = unquote(Module.concat(response_module, "BinaryProtocol"))
        request =
          {unquote(msg_type), unquote(rpc_name), args, serialize_module, deserialize_module}
        timeout = opts[:timeout] || 5_000
        Mux.Client.sync_dispatch(dest, %{}, request, timeout)
      end

      def unquote(underscored_name)(dest, unquote_splicing(vars)) do
        unquote(underscored_options_name)(dest, unquote_splicing(vars), [])
      end

      unquote(def_type)(unquote(options_bang_name)(dest, unquote_splicing(vars), opts)) do
        case unquote(underscored_options_name)(dest, unquote_splicing(vars), opts) do
          {:ok, rsp} ->
            rsp
          :nack ->
            :nack
          {:error, ex} ->
            raise ex
        end
      end

      def unquote(bang_name)(dest, unquote_splicing(vars)) do
        unquote(options_bang_name)(dest, unquote_splicing(vars), [])
      end
    end
  end
end
