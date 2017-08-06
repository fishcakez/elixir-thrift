defmodule Thrift.Generator.Binary.Mux.Server do
  @moduledoc false
  alias Thrift.Generator.{
    Service,
    Utils
  }
  alias Thrift.Parser.FileGroup
  alias Thrift.Parser.Models.Function

  def generate(service_module, service, file_group) do
    functions = service.functions
    |> Map.values
    |> Enum.map(&generate_handler_function(file_group, service_module, &1))
    |> Utils.merge_blocks
    |> Utils.sort_defs

    quote do
      defmodule Binary.Mux.Server do
        @moduledoc false
        @behaviour Mux.ServerApplication
        require Logger

        def start_link(handler_module, dest, port, opts \\ []) do
          present = {Thrift.Binary.Mux.ServerPresentation, __MODULE__}
          opts = [presentation: present, port: port] ++ opts
          Mux.Server.start_link(__MODULE__, dest, handler_module, opts)
        end

        def init(handler_module),
          do: {:ok, [Mux.Deadline, Mux.Trace], handler_module}

        def terminate(_, _),
          do: :ok

        unquote_splicing(functions)
      end
    end
  end

  def generate_handler_function(file_group, service_module, %Function{params: []} = function) do
    fn_name = Atom.to_string(function.name)

    response_module = service_module
    |> Module.concat(Service.module_name(function, :response))

    msg_type = if function.oneway, do: :oneway, else: :call

    quote [generated: true] do
      def __route__(unquote(msg_type), unquote(fn_name)) do
        serialize_module = unquote(Module.concat(response_module, "BinaryProtocol"))
        {nil, unquote(function.name), serialize_module}
      end

      def dispatch(_, _, {unquote(function.name), nil}, handler_module) do
        unquote(build_handler_call(file_group, function, response_module))
      end
    end
  end

  def generate_handler_function(file_group, service_module, function) do
    fn_name = Atom.to_string(function.name)
    args_module = service_module
    |> Module.concat(Service.module_name(function, :args))

    response_module = service_module
    |> Module.concat(Service.module_name(function, :response))

    struct_matches = function.params
    |> Enum.map(fn param ->
      {param.name, Macro.var(param.name, nil)}
    end)

    msg_type = if function.oneway, do: :oneway, else: :call

    quote [generated: true] do
      def __route__(unquote(msg_type), unquote(fn_name)) do
        deserialize_module = unquote(Module.concat(args_module, "BinaryProtocol"))
        serialize_module = unquote(Module.concat(response_module, "BinaryProtocol"))
        {deserialize_module, unquote(function.name), serialize_module}
      end

      def dispatch(_, _,
          {unquote(function.name),
           %unquote(args_module){unquote_splicing(struct_matches)}}, handler_module) do
        unquote(build_handler_call(file_group, function, response_module))
      end
    end
  end

  defp build_handler_call(file_group, function, response_module) do
    handler_fn_name = Utils.underscore(function.name)
    handler_args = function.params
    |> Enum.map(&Macro.var(&1.name, nil))

    quote do
      rsp = handler_module.unquote(handler_fn_name)(unquote_splicing(handler_args))
      unquote(build_responder(function.return_type, response_module))
    end
    |> wrap_with_try_catch(function, file_group, response_module)
  end

  defp wrap_with_try_catch(quoted_handler, function, file_group, response_module) do
    rescue_blocks = function.exceptions
    |> Enum.flat_map(fn
      exc ->
        resolved = FileGroup.resolve(file_group, exc)
        dest_module = FileGroup.dest_module(file_group, resolved.type)
        error_var = Macro.var(exc.name, nil)
        field_setter = quote do: {unquote(exc.name), unquote(error_var)}

        quote do
          unquote(error_var) in unquote(dest_module) ->
            {:ok, %unquote(response_module){unquote(field_setter)}}
        end
    end)

    quote do
      try do
        unquote(quoted_handler)
      rescue
        unquote(rescue_blocks)
      catch kind, reason ->
        formatted_exception = Exception.format(kind, reason, System.stacktrace)
        Logger.error("Exception not defined in thrift spec was thrown: #{formatted_exception}")
        err = Thrift.TApplicationException.exception(
          type: :internal_error,
          message: "Server error: #{formatted_exception}")
        {:ok, err}
      end
    end
  end

  defp build_responder(:void, _) do
    quote do
      _ = rsp
      {:ok, :nil}
    end
  end

  defp build_responder(_, response_module) do
    quote do
      {:ok, %unquote(response_module){success: rsp}}
    end
  end
end
