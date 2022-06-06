#
#  Created by Boyd Multerer on June 18, 2018.
#  Heavily updated 2021/09/01
#  Copyright 2018-2021 Kry10 Limited
#
#  track messages from a multi-touch driver, translate them, and send up to the viewport
#
defmodule Scenic.Driver.Nerves.Touch do
  @opts_schema [
    name: [type: {:or, [:atom, :string]}],
    device: [required: true, type: :string],
    limit_ms: [type: :non_neg_integer, default: 28],
    device_retry_ms: [type: :pos_integer, default: 2000],
    calibration: [required: true, type: {:custom, __MODULE__, :valid_calibration, [:calibration]}]
  ]

  @moduledoc """
  # scenic_driver_nerves_touch

  The main driver for receiving touch input on Nerves devices.

  So far only tested on Raspberry Pi 3 devices. In other words, it is still early
  days for this driver. There will probably be changes in the future. Especially
  regarding multi-touch.

  For now, the events coming to a scene via the touch driver look like the
  same cursor oriented events that come from glfw with a mouse.

  ## Installation

  In your Nerves applications dependencies include the following line

      ...
      {:scenic_driver_nerves_touch, , "~> 0.9"}
      ...

  You do not need to include it in the "host" mix target deps. There you should be
  using the glfw driver and that will take care of the touch input for you.

  ## Configuration

  Configure the touch driver the same way you configure other drivers. Add it
  to the driver list in your ViewPort's config.exs file.

      config :sample, :viewport, %{
            size: {800, 480},
            default_scene: {Sample.Scene.Simple, nil},
            drivers: [
              [
                module: Scenic.Driver.Nerves.Rpi,
              ],
              [
                module: Scenic.Driver.Nerves.Touch,
                device: "FT5406 memory based driver",
                calibration: {{1,0,0},{0,1,0}},
              ],
            ]
          }

  Supported options:\n#{NimbleOptions.docs(@opts_schema)}

  ## Device Name

  __This is important__

  You need to supply the name of the OS driver you are getting the touch information from.
  You don't need to supply the entire string, but what you supply must be in the
  actual device name.

  When you use the sample scene set up by scenic.new.nerves, it will display the
  available device names. Otherwise, use the hex package [input_event](https://hex.pm/packages/input_event) to enumerate them.

  Note that some drivers take a short time to come online. (I'm looking at you FT5406).
  Don't be surprised if touch doesn't work for a second or two after the rest of the
  UI starts to work. Other drivers initialize themselves faster.

  The device name is this part of the configuration

      device: "FT5406 memory based driver",

  ## Calibration

  Calibration maps the resolution/coordinates of the touch screen to the
  coordinates and scale of the display. On the official Raspberry Pi
  7" touch screen, then are the same, so the mapping is easy (1.0).

  However, with other displays (I have a Dell touchscreen I've tested with),
  that is not the case and you need to provide a proper mapping. The values
  are sufficient to support some rotation and out-of-alignment issues in
  the future, but I haven't written a calibration scene yet to provide
  those values in an easy/automatic way.

  ## Calibration Data

  `{{ax, bx, dx}, {ay, by dy}}`

  When a location `{x, y}` comes in from the touch screen, it is projected
  by the calibration data via the formula

      final_x = x * ax + y * bx + dx
      final_y = x * ay + y * by + dy

  See [Calibration in touch-screen systems](http://www.ti.com/lit/an/slyt277/slyt277.pdf) for more information.

  If the touch panel is not rotate or otherwise out of alignment, then you can supply
  a simple calibration by providing scale factors for `ax` and `ay`.

  The calibration is this part of the configuration

      calibration: {{1,0,0},{0,1,0}}
  """

  use Scenic.Driver

  require Logger

  def valid_calibration({{ax, bx, dx}, {ay, by, dy}} = c, _)
      when is_number(ax) and is_number(bx) and is_number(dx) and
             is_number(ay) and is_number(by) and is_number(dy) do
    {:ok, c}
  end

  def valid_calibration(data, name) do
    {
      :error,
      """
      #{IO.ANSI.red()}#{__MODULE__}: Invalid #{inspect(name)} option.
      Must be in the format of {{ax, bx, dx},{ay, by, dy}} where all values are numbers.
      Example for the standard pi 7" touchscreen: {{1,0,0},{0,1,0}}
      #{IO.ANSI.yellow()}Received: #{inspect(data)}
      #{IO.ANSI.default_color()}
      """
    }
  end

  @impl Scenic.Driver
  def validate_opts(opts), do: NimbleOptions.validate(opts, @opts_schema)

  # ============================================================================
  # client callable api

  @doc """
  Retrieve stats about the driver
  """
  def query_stats(pid), do: GenServer.call(pid, :query_stats)

  # ============================================================================
  # startup

  @impl Scenic.Driver
  def init(driver, opts) do
    Logger.info("#{inspect(__MODULE__)}: start: #{inspect(opts)}")

    device = opts[:device]
    Process.send(self(), :init_driver, [])

    driver =
      assign(driver,
        device: device,
        event_path: nil,
        event_pid: nil,
        touch: false,
        position: {0, 0},
        abs_x: 0,
        abs_y: 0,
        # slot: 0,
        # fingers: %{},
        # mouse_x: nil,
        # mouse_y: nil,
        # mouse_event: nil,
        device_retry_ms: opts[:device_retry_ms],
        calibration: opts[:calibration]
      )

    {:ok, driver}
  end

  # ============================================================================

  # --------------------------------------------------------
  # We are starting up.
  # Enumerate the events/device pairs and look for the requested device.
  # If it is NOT found, log a warning and try again later (it might not be loaded yet)
  # If it is found, connect and start working for real
  @impl GenServer
  def handle_info(:init_driver, %{assigns: %{device: device}} = driver) do
    InputEvent.enumerate()
    |> Enum.find_value(fn
      # input_event 0.3.1
      {event, device_name} when is_binary(device_name) ->
        if device_name =~ device do
          event
        else
          nil
        end

      # input_event >= 0.4.0
      {event, info} when is_map(info) ->
        if info.name =~ device do
          event
        else
          nil
        end
    end)
    |> case do
      nil ->
        Logger.warn("#{inspect(__MODULE__)}: Device not found: #{inspect(device)}")
        # not found. Try again later
        {:ok, retry_ms} = fetch(driver, :device_retry_ms)
        Process.send_after(self(), :init_driver, retry_ms)
        {:noreply, driver}

      event ->
        # start listening for input messages on the event file
        {:ok, pid} = InputEvent.start_link(event)
        {:noreply, assign(driver, event_pid: pid, event_path: event)}
    end
  end

  # --------------------------------------------------------
  # first handling for the input events we care about
  def handle_info(
        {:input_event, source, events},
        %{assigns: %{event_path: event_path}} = driver
      )
      when source == event_path do
    {:noreply, track_events(events, driver)}
  end

  # --------------------------------------------------------
  def handle_info(_msg, driver) do
    {:noreply, driver}
  end

  # ============================================================================
  # we only simulate a mouse for now, so use simplified single-finger logic

  defp track_events(
         events,
         %{assigns: %{touch: old_touch, position: old_position}} = driver
       ) do
    # first process the events so we have the latest state
    driver = process_events(driver, events)
    %{assigns: %{touch: new_touch, position: new_position}} = driver

    # if the position changed, send cursor_pos
    driver =
      case new_position != old_position do
        true -> send_input(driver, {:cursor_pos, new_position})
        false -> driver
      end

    # if the button/touch state changed. send cursor_button
    case new_touch do
      ^old_touch -> driver
      true -> send_input(driver, {:cursor_button, {:btn_left, 1, [], new_position}})
      false -> send_input(driver, {:cursor_button, {:btn_left, 0, [], new_position}})
    end
  end

  defp process_events(%{assigns: %{calibration: calibration}} = driver, events) do
    # process each individual event
    driver = Enum.reduce(events, driver, &process_event(&1, &2))

    # transform the position into usable coordinates
    position = {get(driver, :abs_x), get(driver, :abs_y)}
    position = project_pos(position, calibration)
    assign(driver, :position, position)
  end

  defp process_event(event, driver) do
    case event do
      {:ev_abs, :abs_x, x} -> assign(driver, :abs_x, x)
      {:ev_abs, :abs_y, y} -> assign(driver, :abs_y, y)
      {:ev_key, :btn_touch, 1} -> assign(driver, :touch, true)
      {:ev_key, :btn_touch, 0} -> assign(driver, :touch, false)
      evt -> driver
    end
  end

  #   # ============================================================================

  #   # like put_in, except it makes the intermediate maps as needed
  #   @spec put_in_mk( map, list[atom], any ) :: map
  #   defp put_in_mk( map, keys, value )
  #   defp put_in_mk( %{} = map, [key], value ), do: Map.put( map, key, value )
  #   defp put_in_mk( %{} = map, [key | tail], value ) do
  #     inner_map = Map.get( map, key, %{} )
  #       |> put_in_mk( tail, value )
  #     Map.put( map, key, inner_map )
  #   end

  #   defp ev_abs(event, driver)

  #   defp ev_abs({:ev_abs, :abs_mt_slot, slot}, driver) do
  #     assign( driver, slot: slot )
  #   end

  #   # stop tracking the current slot
  #   defp ev_abs(
  #          {:ev_abs, :abs_mt_tracking_id, -1},
  #          %{assigns: %{fingers: fingers, slot: slot}} = driver
  #        ) do
  #     assign( driver, fingers: Map.delete(fingers, slot) )
  #   end

  #   # start tracking a slot
  #   defp ev_abs(
  #          {:ev_abs, :abs_mt_tracking_id, id},
  #          %{assigns: %{fingers: fingers, slot: slot}} = driver
  #        ) do
  #     fingers =
  #       fingers
  #       |> Map.put(slot, %{id: id})
  #     assign( driver, fingers: fingers )
  #   end

  #   # set the x position
  #   defp ev_abs(
  #          {:ev_abs, :abs_x, x},
  #          %{assigns: %{fingers: fingers, slot: slot}} = driver
  #        ) do
  # # Logger.warn("abs_x - fingers: #{inspect(fingers)}, slot: #{inspect(slot)}")
  #     fingers = put_in_mk(fingers, [slot, :x], x)
  # # Logger.warn("out - fingers: #{inspect(fingers)}")
  #     assign( driver, fingers: fingers )
  #   end

  #   defp ev_abs(
  #          {:ev_abs, :abs_mt_position_x, x},
  #          %{assigns: %{fingers: fingers, slot: slot}} = driver
  #        ) do
  #     fingers = put_in_mk(fingers, [slot, :x], x)
  #     assign( driver, fingers: fingers )
  #   end

  #   # set the y position
  #   defp ev_abs(
  #          {:ev_abs, :abs_y, y},
  #          %{assigns: %{fingers: fingers, slot: slot}} = driver
  #        ) do
  # # Logger.warn("abs_y - fingers: #{inspect(fingers)}, slot: #{inspect(slot)}")
  #     fingers = put_in_mk(fingers, [slot, :y], y)
  # # Logger.warn("out - fingers: #{inspect(fingers)}")
  #     assign( driver, fingers: fingers )
  #   end

  #   defp ev_abs(
  #          {:ev_abs, :abs_mt_position_y, y},
  #          %{assigns: %{fingers: fingers, slot: slot}} = driver
  #        ) do
  #     fingers = put_in_mk(fingers, [slot, :y], y)
  #     assign( driver, fingers: fingers )
  #   end

  #   defp ev_abs(
  #          {:ev_abs, :abs_mt_pressure, pressure},
  #          %{assigns: %{fingers: fingers, slot: slot}} = driver
  #        ) do
  #     fingers = put_in_mk(fingers, [slot, :pressure], pressure)
  #     assign( driver, fingers: fingers )
  #   end

  #   defp ev_abs(
  #          {:ev_abs, :abs_mt_distance, distance},
  #          %{assigns: %{fingers: fingers, slot: slot}} = driver
  #        ) do
  #     fingers = put_in_mk(fingers, [slot, :distance], distance)
  #     assign( driver, fingers: fingers )
  #   end

  #   defp ev_abs(
  #          {:ev_key, :btn_touch, 1},
  #          %{assigns: %{slot: _slot}} = driver
  #        ) do
  #     assign( driver, touch: true )
  #   end

  #   defp ev_abs(
  #          {:ev_key, :btn_touch, 0},
  #          %{assigns: %{slot: _slot}} = driver
  #        ) do
  #     assign( driver, touch: false )
  #   end

  #   # if other ev types need to be handled, add them here

  #   defp ev_abs(msg, driver) do
  # # Logger.warn("#{inspect(__MODULE__)}: Unhandled ev_abs: #{inspect(msg)}")
  #     # IO.puts "EV unhandled: #{inspect(msg)}"
  #     driver
  #   end

  #   # ============================================================================
  #   # translate raw events into simulated mouse state

  #   defp simulate_mouse(driver, ev)

  #   defp simulate_mouse(
  #          %{assigns: %{slot: 0}} = driver,
  #          {:ev_abs, :abs_mt_tracking_id, -1} = msg
  #        ) do
  # # Logger.warn("#{inspect(__MODULE__)}: #{inspect(msg)}")
  #     assign( driver, mouse_event: :mouse_up )
  #   end

  #   defp simulate_mouse(
  #          %{assigns: %{slot: 0}} = driver,
  #          {:ev_abs, :abs_mt_tracking_id, _id} = msg
  #        ) do
  # # Logger.warn("#{inspect(__MODULE__)}: #{inspect(msg)}")
  #     assign( driver, mouse_event: :mouse_down )
  #   end

  #   defp simulate_mouse(
  #          %{assigns: %{slot: 0, mouse_event: nil}} = driver,
  #          {:ev_abs, :abs_mt_position_x, x}
  #        ) do
  #     assign( driver, mouse_event: :mouse_move, mouse_x: x )
  #   end

  #   defp simulate_mouse(
  #          %{assigns: %{slot: 0, mouse_event: nil}} = driver,
  #          {:ev_abs, :abs_x, x}
  #        ) do
  #     assign( driver, mouse_event: :mouse_move, mouse_x: x )
  #   end

  #   defp simulate_mouse(
  #          %{assigns: %{slot: 0}} = driver,
  #          {:ev_abs, :abs_mt_position_x, x}
  #        ) do
  #     assign( driver, mouse_x: x )
  #   end

  #   defp simulate_mouse(
  #          %{assigns: %{slot: 0, mouse_event: nil}} = driver,
  #          {:ev_abs, :abs_mt_position_y, y}
  #        ) do
  #     assign( driver, mouse_event: :mouse_move, mouse_y: y )
  #   end

  #   defp simulate_mouse(
  #          %{assigns: %{slot: 0, mouse_event: nil}} = driver,
  #          {:ev_abs, :abs_y, y}
  #        ) do
  #     assign( driver, mouse_event: :mouse_move, mouse_y: y )
  #   end

  #   defp simulate_mouse(
  #          %{assigns: %{slot: 0}} = driver,
  #          {:ev_abs, :abs_mt_position_y, y}
  #        ) do
  #     assign( driver, mouse_y: y )
  #   end

  #   # ignore everything else
  #   defp simulate_mouse(driver, _), do: driver

  #   # ============================================================================
  #   # send simulated mouse events after handling a batch of raw events

  #   defp send_mouse(driver)

  #   # send cursor_button press. no modifiers
  #   defp send_mouse(
  #     %{assigns: %{mouse_x: x, mouse_y: y, mouse_event: :mouse_down } } = driver
  #   ) when is_number(x) and is_number(y) do
  #     # IO.puts "MOUSE press: #{inspect({x,y})}"
  #     pos = project_pos({x, y}, driver)
  #     send_input(driver, {:cursor_button, {:left, :press, 0, pos}})
  #     assign( driver, mouse_event: nil )
  #   end

  #   # send cursor_button release. no modifiers
  #   defp send_mouse(
  #     %{assigns: %{mouse_x: x, mouse_y: y, mouse_event: :mouse_up}} = driver
  #   ) when is_number(x) and is_number(y) do
  #     # IO.puts "MOUSE release: #{inspect({x,y})}"
  #     pos = project_pos({x, y}, driver)
  #     send_input(driver, {:cursor_button, {:left, :release, 0, pos}})
  #     assign( driver, mouse_x: nil, mouse_y: nil, mouse_event: nil )
  #   end

  #   # send cursor_pos. no modifiers
  #   defp send_mouse(
  #     %{assigns: %{mouse_x: x, mouse_y: y, mouse_event: :mouse_move}} = driver
  #   ) when is_number(x) and is_number(y) do
  #     # IO.puts "MOUSE move: #{inspect({x,y})}"
  #     pos = project_pos({x, y}, driver)
  #     send_input(driver, {:cursor_pos, pos})
  #     assign( driver, mouse_event: nil )
  #   end

  #   # generic mouse_up catch-all. For some reason a x or y was never set, so
  #   # this is invalid and the mouse state should be cleared
  #   defp send_mouse(%{assigns: %{mouse_event: :mouse_up}} = driver) do
  #     assign( driver, mouse_x: nil, mouse_y: nil, mouse_event: nil )
  #   end

  #   # fall-through. do nothing
  #   defp send_mouse(driver), do: driver

  # --------------------------------------------------------
  # project the measured x value by the calibration data to get the screen x
  # defp project_pos({x, y}, %{assigns: %{calibration: {{ax, bx, dx}, {ay, by, dy}} }}) do
  #   {
  #     x * ax + y * bx + dx,
  #     x * ay + y * by + dy
  #   }
  # end

  defp project_pos({x, y}, {{ax, bx, dx}, {ay, by, dy}}) do
    {
      x * ax + y * bx + dx,
      x * ay + y * by + dy
    }
  end

  # defp project_pos(pos, _), do: pos
end
