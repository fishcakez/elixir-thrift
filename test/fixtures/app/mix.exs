defmodule App.Mixfile do
  use Mix.Project

  def project do
    [app: :app,
     version: "1.0.0",
     thrift_executable: System.get_env("THRIFT") || "thrift",
     thrift_files: Mix.Utils.extract_files(["thrift"], [:thrift])]
  end
end
