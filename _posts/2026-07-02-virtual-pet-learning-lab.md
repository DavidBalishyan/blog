---
layout: post
title: "Building a Virtual Pet at TUMO's Embedded C++ Lab"
date: 2026-07-02 12:00:00 +0400
categories: [c, embedded]
tags: [esp32, m5stickc, cpp, platformio, learning-lab, iot, tumo]
published: true
---

I'm partway through a learning lab at TUMO Center for Creative Technologies where we're building a Tamagotchi-style virtual pet for the M5StickC Plus 2. Seven sessions, one cumulative project, from a blank screen to a WiFi-connected pet you can feed from your phone. We're past the halfway point and I wanted to write down how it works so far.

## The Hardware

The M5StickC Plus 2 is a tiny ESP32-PICO-V3-02 board with a 135x240 color LCD, three buttons, a buzzer, a microphone, and an MPU6886 accelerometer. It costs about $15 and runs on the Arduino framework through PlatformIO. The form factor is perfect for a virtual pet - small enough to carry around, the screen big enough to show a character, and the accelerometer lets you interact by tilting and shaking.

## How the Pet Works

The pet has eight stats that decay over time: fullness, happiness, energy, cleanliness, sickness, hydration, tiredness, and sadness. Each one drifts toward zero at a configurable rate. If you neglect them, bad things happen. Let fullness hit zero and the pet dies.

The core is a state machine with nine states: IDLE, EATING, SLEEPING, PLAYING, SICK, HEALING, BATHING, DRINKING, and DEAD. While eating, fullness recovers. While sleeping, energy recovers. The state machine prevents stacking actions - you can't eat and sleep at the same time.

A mood system sits on top of the stats. The `computeMood()` function uses a priority ladder: if sickness is above 50, the pet looks unwell. If fullness is below 30, it looks hungry. If happiness is above 70, it looks happy. Otherwise it's neutral. Each mood maps to a different 80x80 sprite drawn from flash memory in RGB565 format.

```cpp
if (sickness > 50) return MoodSprite::UNWELL;
if (fullness < 30) return MoodSprite::HUNGRY;
if (hydration < 30) return MoodSprite::THIRSTY;
if (happiness > 70) return MoodSprite::HAPPY;
return MoodSprite::NEUTRAL;
```

The rendering uses double-buffering with `M5Canvas` to eliminate flicker. Every frame draws to an off-screen canvas, then pushes the result to the display. The main loop never calls `delay()` - everything is driven by `millis()` comparisons, so button presses and stat decay are never blocked.

## Architecture

The firmware is split into about a dozen classes, each with one job. They're created and wired together in `main.cpp`:

- **Pet** - Stats, state machine, mood computation
- **DisplayManager** - Drawing to the screen
- **AnimationManager** - Frame cycling for sprite animation
- **ButtonHandler** - Edge detection on button presses
- **ActionMenu** - Cycling and confirming menu actions
- **ImuManager** - Accelerometer reads and shake detection
- **TiltMotion** - Smoothing raw tilt into pixel offsets
- **NavigationManager** - Screen transitions (Main, Stats, Interact)
- **SpeakerManager** - Buzzer melodies and alerts
- **TimeManager** - Automatic stat decay timing
- **StorageManager** - NVS flash save/load
- **WirelessManager** - WiFi AP, HTTP server, WebSocket updates

Every feature is gated behind an `#ifdef ENABLE_*` flag. Each session enables one more flag, so the code compiles with only the features we've covered so far. This means we never see code we're not supposed to understand yet.

## The Sessions (What We've Covered So Far)

Each session builds on the previous one. Nothing gets thrown away.

1. **Session 1** - Boot sequence, screen initialization, one stat that decays, one placeholder sprite
2. **Session 2** - Action menu with feed, play, sleep, bathe, heal, drink, save options
3. **Session 3** - Accelerometer: shake to play, tilt to slide the sprite around the screen
4. **Session 4** - Buzzer melodies and alert sounds (different tunes for feeding, death, waking up)

We just finished session 4. The pet can be fed, played with by shaking, put to sleep, and it plays a little tune during each action. It also beeps at you when it's hungry or sick. Having a device that makes sounds on purpose is more satisfying than I expected.

We still have three sessions ahead: NVS persistence (stats survive unplugging), multiple screens with mood sprites, and the WiFi dashboard with live WebSocket updates. I'm most looking forward to the dashboard.

## Testing

The project includes unit tests using the Unity test framework, runnable on a laptop (no hardware needed). Hardware headers are replaced with mock stubs so `pio test -e native` runs in under a second. There are 35 tests for the Pet module alone. It's been useful for catching regressions - when we refactor something for a new session, we can run the tests and see if we broke old functionality.

## What I Think So Far

Building something concrete is the whole reason this works. If the sessions were disconnected exercises I'd forget them. Instead I have a device on my desk that runs code I wrote, and every session adds something new without removing what was there before.

Session 3 was the moment it clicked for me. We had the accelerometer working and the sprite would slide around the screen when you tilted the device. That's not a big feature in terms of lines of code, but it's the first time I felt like the device was responding to the physical world rather than just executing instructions. The buzzer in session 4 had a similar feel - code producing sound through a physical speaker.

The project is on GitHub at [DavidBalishyan/virtual-pet](https://github.com/DavidBalishyan/virtual-pet) if you want to follow along. 
