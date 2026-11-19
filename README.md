# Pull Timer

A macOS menu bar timer you set by pulling its icon. The further you pull, the longer the timer.

![One timer running while a second is pulled with Option held](docs/demo.gif)

*One timer running while a second is set with Option held. The animation is rendered by the app's own drawing code over a mock desktop.*

## Use

- **Set a timer:** drag the menu bar icon in any direction. The label next to the icon shows the duration and when it will ring. Release to start.
- **Stops:** 30 s, 1, 2, 3, 5, 7, 10, 15, 20, 30, 45, 60 and 90 min, then 2, 3, 4, 6, 8, 12 and 24 h. Each stop is 28 points of pull.
- **Timer 2:** hold Option while pulling to set a second, independent timer.
- **Cancel:** pull a short distance and release inside the dead zone, or use the menu.
- **Menu:** click or right-click the icon. It has cancel, restore of a cancelled or replaced timer, a log of recent events, a toggle for scale marks along the pull line, and launch at login.
- **Time's up:** a chime, a notification, a banner in the middle of the screen, and a blinking "Time's up" in the menu bar until you click either. The banner can be turned off in the menu.
- **Pomodoro:** hold Shift while pulling to start a pomodoro: the pull sets the focus length (15 to 90 min), the break is a fifth of it and the long break three fifths. "Start pomodoro" in the menu repeats the last one. By default it runs 25 min focus and 5 min breaks on timer 1, with a 15 min break after every fourth focus. Each phase starts by itself, and the menu bar icon turns into a tomato (red during focus, outlined during breaks) next to "focus" or "break" and the countdown. Stop it from the menu or by pulling a new timer 1. "Pomodoro settings" in the menu sets the focus, break and long break lengths and the number of focus rounds before a long break; a change applies from the next phase.

The log is written to `~/Library/Logs/PullTimer.log`.

## Build

Requires macOS 13 or later and the Xcode command line tools.

```sh
./build.sh
open "build/Pull Timer.app"
```

The app is a single Swift file with no dependencies. `build.sh` compiles it, generates the app icon, and ad-hoc signs the bundle. It is not notarized, so a copy downloaded from elsewhere needs "Open Anyway" in System Settings → Privacy & Security on first launch. Building it yourself avoids that.
