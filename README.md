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
              module: Scenic.Driver.Local,
              position: [scaled: true, centered: true, orientation: :normal]
            ],
            [
              module: Scenic.Driver.Nerves.Touch,
              device: "raspberrypi-ts",
              calibration: {{1, 0, 0}, {0, 1, 0}}
            ]
          ]
        }

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

**Note:** If you're using `nerves_system_rpi3` version 1.13.1 or later the device name for the
official Raspberry pi 7" touch screen is `raspberrypi-ts` instead of `FT5406 memory based driver`

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
