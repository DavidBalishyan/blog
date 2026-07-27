---
layout: post
title: "Finishing the Virtual Pet"
date: 2026-07-27 12:00:00 +0400
categories: [c, embedded]
tags: [esp32, m5stickc, cpp, platformio, websockets, assembly, testing, tumo]
published: true
---

At the beginning of July I wrote about the [virtual pet I was building at TUMO]({% post_url 2026-07-02-virtual-pet-learning-lab %}). At that point I was four sessions in. The pet could eat, sleep, play, move when I tilted the M5StickC, and make a few noises. Persistence, multiple screens, mood sprites, and the web dashboard were still on the to-do list.

I finished them. Then, as usual, I kept going.

The finished project still has the same basic loop: read the inputs, update the pet, draw the current screen, repeat. It now saves its state, keeps track of time while powered off, serves a control panel over WiFi, streams updates through WebSockets, plays full songs without freezing the game, and measures rendering time with the ESP32's CPU cycle counter.

## Making the Pet Survive a Reboot

The first unfinished piece was persistence. The ESP32 has non-volatile storage, so I used the Arduino `Preferences` API to save the pet's name and stats. On startup, `StorageManager` loads the saved values before the display and wireless dashboard begin using them.

Saving the numbers was easy. Time was the part that needed more thought.

If the device is unplugged for two hours, should the pet wake up exactly as it was? That would make saving less like persistence and more like pausing. The M5StickC Plus 2 has a BM8563 real-time clock, so I used its timestamp for the decay timers. Each timer stores the last time it ran. After a reboot, it compares that saved value with the current RTC time and applies however many whole decay intervals passed in between.

The shared calculation ended up small enough to isolate:

```cpp
time_t elapsed = now - *last;
if (elapsed < interval) return 0;

int ticks = elapsed / interval;
*last = now - (elapsed % interval);
return ticks;
```

Keeping the remainder matters. If a stat changes every 60 seconds and 75 seconds have passed, one tick should run and the other 15 seconds should carry over. Resetting the timer to `now` would quietly lose that time on every update.

There are also two awkward cases: the first call has no previous timestamp, and an RTC can move backwards if it is reset. In both cases the timer resynchronizes without applying a huge or negative decay.

## More Screen, More Personality

The first version put almost everything on one screen. That worked while there were only a few controls, but it became crowded once all eight stats and actions were enabled.

The final UI has separate Main, Stats, and Interact screens. The main screen is for the pet itself, the Stats screen shows the bars, and Interact contains the action menu. `NavigationManager` owns the current screen and button transitions; it does not know how the pet or menu works.

I also replaced the placeholder face with mood sprites. The pet can look happy, hungry, thirsty, unwell, or neutral. Mood is computed from the stats using a priority order, so sickness wins over happiness and a thirsty pet does not smile just because its happiness value happens to be high.

This sounds like a cosmetic change, but it made the project feel finished more than most of the lower-level work did. A row of correct numbers is useful for debugging. A face that looks annoyed because I forgot to feed it feels like a pet.

I added an RTC clock widget too. It is a small detail, but it belongs on this kind of pocket device and gave the real-time clock a visible purpose beyond doing timer arithmetic in the background.

## The ESP32 Became the Server

The web dashboard was the feature I was looking forward to in the first post. It became the biggest addition to the project.

When wireless support is enabled, the ESP32 creates an open access point named `VirtualPet`. I connect a phone or laptop to it and open `192.168.4.1`. No router and no internet connection are involved. The HTML, CSS, and JavaScript are compiled into the firmware and served directly by the pet.

The first dashboard only displayed the stats. I changed it to use a WebSocket on port 81, with the ESP32 broadcasting fresh JSON twice per second:

```json
{
  "pet": {
    "name": "Pixel",
    "mood": "happy",
    "alive": true
  },
  "stats": {
    "fullness": 82,
    "happiness": 76,
    "energy": 64
  },
  "brightness": 75
}
```

The connection works in both directions. The browser receives live stats, but it can also send commands back to the device. From the dashboard I can feed, play with, bathe, heal, or reset the pet. I can save its state, rename it, and change the display brightness with a slider.

That two-way connection was the point where the project stopped feeling like a demo page attached to an embedded program. The browser and the physical buttons are now two interfaces to the same pet. Pressing Feed on my phone changes the state on the M5StickC, and the next WebSocket update confirms the result everywhere.

I kept the dashboard assets as ordinary `.html`, `.css`, and `.js` files instead of writing giant C++ string literals. The build converts them into headers that can live in flash. Editing a web page as escaped C++ is miserable, and there was no reason to make myself do that.

## I Accidentally Added a Music Player

The short action sounds from session four use `delay()`. A half-second feeding jingle can get away with blocking the loop. A complete tune cannot; the screen, buttons, WebSocket, and timers would all stop until the song ended.

So the longer songs use a non-blocking player. Each tune is an array of pitch and note-length pairs. `startSong()` begins the first note, and `updateSong()` advances by one note when its time slot expires. The main loop calls it on every pass, so the rest of the pet continues running.

```cpp
struct SongNote {
    uint16_t pitch;
    uint16_t length;
};
```

The lengths are musical values such as eighth notes and quarter notes rather than hardcoded milliseconds. The player converts them using the song's tempo. It currently includes Twinkle Twinkle Little Star, Ode to Joy, the Super Mario Bros. theme, and Für Elise. They can all be started and stopped from the dashboard.

Was a four-song buzzer player part of the learning lab? No. Once I had WebSocket commands and a speaker in the same project, though, the button was too tempting.

## Assembly, Because Why Not?

Near the end I rewrote the decay-tick calculation in Xtensa assembly. It loads the previous timestamp, checks the edge cases, divides the elapsed time by the interval, stores the adjusted timestamp, and returns the number of ticks.

This was not an optimization the project needed. The C++ version is short, readable, and probably compiled into perfectly reasonable machine code already. I kept it as the reference implementation and made the assembly version optional with `-DUSE_ASM_TIMER`.

The more useful assembly addition is the cycle counter. The ESP32's Xtensa CPU has a `CCOUNT` register that increments every processor cycle. Reading it takes one instruction:

```asm
rsr.ccount a2
```

In debug builds I read it before and after rendering, subtract the values with wrap-safe unsigned arithmetic, and print the result over serial. That gives me a direct measurement of how many CPU cycles a frame costs.

Both modules have host fallbacks. The native unit tests run on x86, where Xtensa assembly cannot compile, so preprocessor guards leave it out and use C++ instead. That let me experiment close to the hardware without sacrificing the quick laptop test loop.

## Finishing the Tooling Too

The project ended with 70 native tests across six suites. Thirty-five cover the `Pet` class; the rest cover sprite animation, tilt smoothing, timer arithmetic, the cycle-counter API, and the non-blocking song player.

I also added a Makefile around PlatformIO:

```console
$ make build
$ make upload
$ make test
$ make lint
```

GitHub Actions runs the native tests, builds the M5StickC firmware, and runs `cppcheck` on every push and pull request. Generated assets are built as part of the correct jobs, so a clean checkout is enough.

The feature flags from the original course are still there. Turning them off walks the project backward: base pet, menu, accelerometer, sound, persistence, multiple screens and moods, then wireless. That matters because the final repository is also the course reference. The finished code should not hide how the project was assembled.

## What Changed After the Halfway Point

When I wrote the first post, the accelerometer was my favorite part because it made software react to the physical world. I still like that interaction, but the dashboard became the part that tied everything together. It forced the pet logic, timers, storage, display, sound, and networking to cooperate without letting one of them take over the main loop.

The last part of the project was less about adding isolated features and more about boundaries. The display should receive values without owning the pet. Navigation should change screens without knowing how an action works. The wireless code needs access to several systems, but the `Pet` class should not know that a browser exists.

Some of those boundaries are imperfect, and there are things I would change in another pass. The short sound effects still block briefly. The dashboard command parser is deliberately small and expects a narrow JSON format. The RTC setup is basic. But the pet works as a complete device instead of feeling like a collection of session exercises.

That is the satisfying part. I started with a blank 135x240 screen and ended with a tiny computer that keeps a creature alive, complains when I neglect it, hosts its own website, and plays Für Elise badly through a buzzer.

The finished source is on [GitHub](https://github.com/DavidBalishyan/virtual-pet).
