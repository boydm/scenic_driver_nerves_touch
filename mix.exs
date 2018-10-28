defmodule ScenicDriverNervesTouch.MixProject do
  use Mix.Project

  def project do
    [
      app: :scenic_driver_nerves_touch,
      version: "0.9.0",
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
      {:input_event, "~> 0.3"},
      {:scenic, git: "git@github.com:boydm/scenic.git"}
    ]
  end

  defp description() do
    """
    Scenic.Driver.Nerves.Rpi - Scenic driver providing touch input for Nerves devices.
    """
  end

  defp package() do
    [
      name: :scenic_driver_nerves_touch,
      maintainers: ["Boyd Multerer"]
    ]
  end
end
