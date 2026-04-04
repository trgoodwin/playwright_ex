defmodule PlaywrightEx.RuntimeTest do
  use ExUnit.Case

  @moduletag timeout: 30_000

  @tag :runtime
  test "launches browser with :runtime option" do
    bun = System.find_executable("bun")

    if bun do
      supervisor_name = :"runtime_test_#{System.unique_integer([:positive])}"
      connection = PlaywrightEx.Supervisor.connection_name(supervisor_name)

      {:ok, sup} =
        PlaywrightEx.Supervisor.start_link(
          name: supervisor_name,
          executable: "assets/node_modules/playwright/cli.js",
          runtime: bun,
          timeout: 10_000
        )

      conn_opts = [timeout: 10_000, connection: connection]

      {:ok, browser} = PlaywrightEx.launch_browser(:chromium, conn_opts)
      {:ok, context} = PlaywrightEx.Browser.new_context(browser.guid, conn_opts)
      {:ok, page} = PlaywrightEx.BrowserContext.new_page(context.guid, conn_opts)
      {:ok, _} = PlaywrightEx.Frame.goto(page.main_frame.guid, [url: "about:blank"] ++ conn_opts)
      {:ok, _} = PlaywrightEx.Browser.close(browser.guid, conn_opts)

      Supervisor.stop(sup)
    else
      IO.puts("Skipping runtime test: bun not found")
    end
  end
end
