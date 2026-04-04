defmodule PlaywrightEx.Supervisor do
  @moduledoc """
  Playwright connection supervision tree.

  Supports two transport modes:
  - Local Port (default): Spawns Node.js playwright driver
  - WebSocket: Connects to remote Playwright server

  ## Options
  - `:ws_endpoint` - WebSocket URL (e.g. `ws://localhost:3000?browser=chromium`).
    If provided, uses WebSocket transport. Otherwise uses local Port.
    If no browser param is provided, `chromium` is used by default.
  - `:executable` - Path to playwright CLI (only for Port transport)
  - `:runtime` - JS runtime to use (e.g. `"bun"`, `"node"`). When set, the runtime is spawned
    as the executable and the playwright CLI path is passed as an argument. When unset, the
    playwright CLI is executed directly via its shebang (requires Node.js). Only for Port transport.
  - `:timeout` - Connection timeout
  - `:js_logger` - Module for logging JS console messages
  - `:name` - Optional name for this supervisor instance. Defaults to `PlaywrightEx.Supervisor`.
    Use this to run multiple independent Playwright connections (e.g., one with PortTransport,
    another with WebSocketTransport). The name is used to derive child process names.

  ## Limitations of WebSocket connection to remote server
  - Single browser type - only the one you set via `ws_endpoint` (the browser type passed to `PlaywrightEx.launch_browser/2` is ignored)
  """

  use Supervisor

  alias PlaywrightEx.Connection
  alias PlaywrightEx.FrameEventRecorder
  alias PlaywrightEx.PortTransport
  alias PlaywrightEx.WebSocketTransport

  @doc """
  Returns the connection process name for a given supervisor name.
  """
  def connection_name(supervisor_name \\ __MODULE__) do
    Module.concat(supervisor_name, "Connection")
  end

  def start_link(opts \\ []) do
    opts =
      Keyword.validate!(opts, [
        :timeout,
        :ws_endpoint,
        :runtime,
        :fail_on_unknown_opts,
        executable: "playwright",
        js_logger: nil,
        name: __MODULE__
      ])

    Supervisor.start_link(__MODULE__, Map.new(opts), name: opts[:name])
  end

  @impl true
  def init(config) do
    connection_name = connection_name(config.name)
    pg_scope = pg_scope_name(config.name)
    frame_event_recorder_registry = FrameEventRecorder.registry_name(connection_name)
    frame_event_recorder_supervisor = FrameEventRecorder.supervisor_name(connection_name)
    {transport_child, transport} = transport_child_spec(config, connection_name)
    pg_child = %{id: pg_scope, start: {:pg, :start_link, [pg_scope]}}

    children = [
      transport_child,
      pg_child,
      {Registry, keys: :unique, name: frame_event_recorder_registry},
      {DynamicSupervisor, strategy: :one_for_one, name: frame_event_recorder_supervisor},
      {Connection,
       [
         [
           name: connection_name,
           timeout: config.timeout,
           js_logger: config.js_logger,
           transport: transport,
           pg_scope: pg_scope
         ]
       ]}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp transport_child_spec(%{ws_endpoint: ws_endpoint, name: name}, connection_name) when is_binary(ws_endpoint) do
    ws_endpoint = add_new_query(ws_endpoint, %{"browser" => "chromium"})

    if !Code.ensure_loaded?(WebSockex) do
      raise """
      WebSocket transport requires the :websockex dependency.

      Add it to your mix.exs:

          {:websockex, "~> 0.4"}
      """
    end

    transport_name = Module.concat(name, "WebSocketTransport")

    # WebSocket transport
    child_spec =
      {WebSocketTransport, ws_endpoint: ws_endpoint, name: transport_name, connection_name: connection_name}

    {child_spec, {WebSocketTransport, transport_name}}
  end

  defp transport_child_spec(%{executable: executable, name: name} = config, connection_name) do
    executable = validate_executable!(executable)
    runtime = validate_runtime!(Map.get(config, :runtime))

    transport_name = Module.concat(name, "PortTransport")

    child_spec =
      {PortTransport, executable: executable, runtime: runtime, name: transport_name, connection_name: connection_name}

    {child_spec, {PortTransport, transport_name}}
  end

  defp validate_runtime!(nil), do: nil
  defp validate_runtime!(runtime), do: find_executable!(runtime)

  defp validate_executable!(executable) do
    if File.exists?(executable), do: executable, else: find_executable!(executable)
  end

  defp find_executable!(name) do
    System.find_executable(name) ||
      raise "Executable not found: #{name}. Ensure it is installed and on `$PATH`."
  end

  defp add_new_query(url, default_params) when is_binary(url) and is_map(default_params) do
    uri = URI.parse(url)
    existing_params = URI.decode_query(uri.query || "")
    merged_params = Map.merge(default_params, existing_params)
    URI.to_string(%{uri | query: URI.encode_query(merged_params)})
  end

  defp pg_scope_name(supervisor_name) do
    Module.concat(supervisor_name, "PgScope")
  end
end
