defmodule ScenicDriverNervesTouch.MixProject do
  use Mix.Project

  @app_name :scenic_driver_nerves_touch
  @version "0.10.0"
  @github "https://github.com/boydm/scenic_driver_nerves_rpi"

  def project do
    [
      app: @app_name,
      version: @version,
      package: package(),
      description: description(),
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:input_event, "~> 0.4"},
      {:scenic, "~> 0.10"},
      {:ex_doc, "~> 0.19", only: [:dev, :test], runtime: false}
    ]
  end

  defp description() do
    """
    Scenic.Driver.Nerves.Touch - Scenic driver providing touch input for Nerves devices.
    """
  end

  defp package do
    [
      name: @app_name,
      contributors: ["Boyd Multerer"],
      maintainers: ["Boyd Multerer"],
      licenses: ["Apache 2"],
      links: %{Github: @github}
    ]
  end
end
