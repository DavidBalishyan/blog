---
layout: post
title: "Inside cboomer: Building a Zooming app for linux"
date: 2026-06-20 12:00:00 +0400
categories: [c, graphics]
tags: [c, x11, opengl, shaders, graphics]
published: true
---

I've mentioned cboomer a few times in previous posts - it's the project I used to experiment with Ninja generators. The README covers the basics, but I haven't done a proper walkthrough of the code and the design decisions, so here it is.

cboomer is a fullscreen screenshot viewer for Linux. You launch it, and it fills your screen with a real-time view of your desktop (or a specific window if you use the select mode). Then you can pan around with the mouse, zoom in and out, and apply GLSL shader effects on top of everything. Want to see your desktop through a CRT monitor simulation? Press `t` a few times. Want to make it look like a VHS tape? Keep pressing `t`. The screenshot refreshes constantly if you build with the `live` flag, so it's like a live camera feed of your screen with real-time filters.

It started as a rewrite of Tsoding's boomer, because I wanted to understand how X11 and OpenGL work together in a single program. Then I kept adding features because each one was interesting to build. Before I knew it, the project had 12 fragment shaders, a camera system with inertia and smooth animations, an on-screen display with TrueType font rendering, a MIT-SHM shared memory capture path, its own PNG encoder, and a build system with stacked make targets.

## How Data Moves Through the Program

The pipeline is simple. There are no threads, no render graphs, no entity component systems. It's just a single loop that does four things:

1. Capture the screen contents into an XImage using X11
2. Upload that pixel data as an OpenGL texture
3. Draw a fullscreen quad with the currently selected fragment shader
4. Process mouse and keyboard events to move the camera, change shaders, toggle effects

That loop runs at your monitor's refresh rate - usually 60 Hz. I use XRandR (`XRRGetScreenInfo` + `XRRConfigCurrentRate`) to detect the actual refresh rate at startup instead of guessing 60.

The most interesting part of the pipeline is probably how the screenshot gets from the X server into OpenGL. X11 gives you pixels in BGRA order - blue byte first, then green, red, alpha. OpenGL's `GL_BGRA` format extension accepts this directly, so I can upload the raw XImage data without any per-pixel conversion:

```c
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, width, height, 0,
             GL_BGRA, GL_UNSIGNED_BYTE, screenshot.image->data);
```

The internal format is `GL_RGB` (OpenGL stores it as RGB internally) but the source format is `GL_BGRA`. OpenGL handles the conversion on upload. I don't need to shuffle bytes around.

## Capturing the Screen

The basic capture uses `XGetImage`, which asks the X server to copy pixels from a window (or the root window) into an XImage on the client side. It works everywhere and it's simple, but it involves a copy through the X server - the server reads its framebuffer, sends the pixels over the socket, and Xlib writes them into the XImage.

For the `live` build variant (where the screenshot refreshes every frame), that copy overhead matters. That's where MIT-SHM comes in. The MIT-SHM extension lets the X server write pixels directly into a shared memory segment that the client allocates. Zero copy through the server. The setup is a bit involved but it's all straightforward system programming:

```c
XImage *img = XShmCreateImage(display, visual, depth, ZPixmap, NULL, &shminfo, width, height);
shminfo.shmid = shmget(IPC_PRIVATE, img->bytes_per_line * img->height, IPC_CREAT | 0777);
shminfo.shmaddr = img->data = shmat(shminfo.shmid, NULL, 0);
shminfo.readOnly = False;
XShmAttach(display, &shminfo);
XShmGetImage(display, window, img, 0, 0, AllPlanes);
```

The cleanup also matters. When you're done with the shared memory, you need to detach it from the X server, detach it from your process, and remove the segment:

```c
XShmDetach(display, &shminfo);
shmdt(shminfo.shmaddr);
shmctl(shminfo.shmid, IPC_RMID, NULL);
```

If any step of the MIT-SHM setup fails - you're over a remote SSH connection where MIT-SHM isn't available, for example - the code falls back to `XGetImage` transparently. I check the return value of `XShmGetImage` and if it's zero, I free the shared memory and fall through to the regular path.

## The Camera System

The camera is a struct with a position vector, a velocity vector, a scale value, and some animation state. Nothing fancy - it's basically a 2D camera with smooth movement.

Dragging the mouse sets the velocity, and each frame the velocity is applied to the position and then decayed by friction:

```c
camera->position.x += camera->velocity.x * dt;
camera->position.y += camera->velocity.y * dt;
float friction_factor = powf(1.0f - config.friction, dt * 60.0f);
camera->velocity.x *= friction_factor;
camera->velocity.y *= friction_factor;
```

The `powf` call is important. If I just did `camera->velocity.x *= (1.0f - friction)` every frame, the decay rate would depend on the frame rate. At 60 FPS the velocity would decay 60 times per second. At 30 FPS it would decay 30 times per second, so the inertia would last longer. The `powf` normalizes the decay to be frame-rate independent. The `dt * 60.0f` part says "this is the decay that would happen in 60 frames" and the powf adjusts it for the actual frame duration.

Zooming was the trickiest part to get right. When you scroll the mouse wheel, the zoom should center on whatever pixel is under the cursor. If you're zoomed in on the top-left corner of the screen and you scroll, the zoom should happen toward that corner, not toward the center of the window. Here's how that works:

```c
Vec2f p0 = vec2_div_f(
    vec2_sub(camera->scale_pivot, vec2_mul_f(window_size, 0.5f)),
    camera->scale);
camera->scale = fmaxf(camera->scale + delta_zoom, config.min_scale);
Vec2f p1 = vec2_div_f(
    vec2_sub(camera->scale_pivot, vec2_mul_f(window_size, 0.5f)),
    camera->scale);
camera->position = vec2_add(camera->position, vec2_sub(p0, p1));
```

The idea is: before the zoom, figure out what world coordinate is under the cursor. After the zoom, figure out what world coordinate is under the cursor again. Adjust the camera position so they're the same. The cursor pixel stays in place while everything else zooms in or out around it.

The scale is clamped to a minimum value from the config file, which defaults to 0.1 (10% zoom). I tried letting users zoom out further but at some point the screenshot becomes so small on screen that the filtering artifacts are distracting.

### Smooth Reset Animation

Pressing `0` triggers a smooth reset - the camera animates from its current position and zoom level back to the default (centered, 100% zoom). The animation uses a cubic smoothstep for easing:

```c
camera->anim_start_pos = camera->position;
camera->anim_start_scale = camera->scale;
camera->anim_end_pos = vec2(0.0f, 0.0f);
camera->anim_end_scale = 1.0f;
camera->anim_t = 0.0f;
camera->animating = 1;
```

Each frame during the animation, `anim_t` increases by `dt / animation_duration` and the interpolation uses `t * t * (3.0f - 2.0f * t)` - the classic smoothstep. The camera position and scale are linearly interpolated between their start and end values, but the interpolation parameter follows the smoothstep curve so it eases in and out. I also use this same system for the zoom preset keys (1 through 5 bind to specific zoom levels).

## The Shader System

This is the part I'm most happy with. cboomer has 12 fragment shaders that you cycle through with the `t` key. Here's the full list:

- **Normal** - just shows the texture with flashlight support
- **Invert** - photographic negative, `1.0 - texel.rgb`
- **CRT** - chromatic aberration offsetting the color channels, scanlines, and vignette darkening at the edges
- **Grayscale** - luminance using Rec.601 weights (`0.299R + 0.587G + 0.114B`)
- **Edge Detection** - Sobel operator with a 3x3 kernel, reads 9 texels per pixel
- **VHS Glitch** - animated horizontal block shifts, color channel offsets, noise bars, and dropout lines
- **Distortion** - animated ripple combined with barrel distortion
- **Zoom Blur** - radial motion blur from the cursor position, sampling 24 points along the blur direction
- **Posterize** - quantizes each color channel to 4 discrete levels
- **Pixelate** - divides the UV space into a grid of large cells, each sampling a single texel
- **Sepia** - classic sepia tone using weighted dot products
- **Emboss** - 3D emboss effect by taking the luminance difference between top-left and bottom-right neighbors

All shaders are embedded into the binary at build time. The script `scripts/gen_shaders.sh` reads every `.glsl` file in `src/shaders/` and generates a C header (`build/shaders.h`) with each shader stored as a `static const char` array:

```c
static const char VERT_SRC[] = "#version 130\nin vec2 aPos;\nin vec2 aTexCoord;\nuniform vec2 cameraPos;\nuniform float cameraScale;\n...";
static const char FRAG_CRT_SRC[] = "#version 130\nout mediump vec4 color;\nuniform sampler2D tex;\nuniform vec2 cameraPos;\n...";
```

This means the binary is completely self-contained. No need to ship `.glsl` files alongside it. They're compiled into the executable at build time.

Every shader receives the same set of uniforms: `cameraPos`, `cameraScale`, `screenshotSize`, `windowSize`, `cursorPos`, `flShadow`, `flRadius`, `mirror`, and `time`. The animated shaders (VHS Glitch, Distortion, Zoom Blur) use `time` to drive their animations. The other shaders just ignore it - GLSL doesn't complain about unused uniforms.

Shader switching is instant because everything is compiled at startup. The `t` key moves an index through the shader array and calls `glUseProgram`. There's a 200ms throttle on the key to prevent cycling through all 12 shaders in a single key-repeat burst:

```c
static Time last_t = 0;
Time now = xev.xkey.time;
if (now - last_t > 200) {
    current_shader = (current_shader + 1) % SHADER_COUNT;
    last_t = now;
}
```

### Developer Mode and Hot Reload

If you build with `make dev` (which sets `-DDEVELOPER`), pressing `Ctrl+R` recompiles all shaders from the `.glsl` files on disk. The code re-reads the files, calls `glCompileShader` and `glLinkProgram` for each one, checks for errors, and swaps in the new programs. This makes iterating on shader effects very fast: edit the GLSL file, save, press Ctrl+R, and see the result immediately.

In developer mode, the shader source code is read from disk at startup instead of using the embedded strings. This means I can modify the shader files while the program is running and hot-reload them. In release mode, the embedded strings are used and the disk files aren't needed.

When a shader fails to compile in developer mode, I print the GL info log to stderr and keep the old program running. This is important because when you're iterating on a shader, you'll inevitably write broken GLSL at some point, and losing the display entirely would be worse than seeing the old shader.

## The Flashlight Effect

Every fragment shader includes a flashlight effect. When you press `f`, the area around the cursor is lit normally and everything outside it is darkened. The shadow intensity and radius are configurable (in the config file or at runtime with `[` and `]`).

The implementation is the same pattern duplicated across all 12 fragment shaders:

```glsl
color = mix(
    texel,
    vec4(0.0, 0.0, 0.0, 0.0),
    length(cursor - gl_FragCoord) < (flRadius * cameraScale) ? 0.0 : flShadow);
```

The `mix` function interpolates between the original texel color and black based on the flashlight condition. If the pixel is within the flashlight radius, the blend factor is 0.0 (show the original color). If it's outside, the blend factor is `flShadow` (some value between 0.0 and 0.8, configurable in the config file).

I duplicated this across all shaders because GLSL doesn't support `#include` without extensions. It's boilerplate, but it's consistent boilerplate, and it means every shader supports the flashlight without needing any special handling.

The flashlight radius and shadow values have their own inertia - pressing `[` or `]` changes `delta_radius`, which decays over time, giving the radius changes a smooth feel instead of instant jumps.

## The On-Screen Display

The OSD shows the current shader name, FPS, the cursor position in screenshot coordinates, the RGB color values of the pixel under the cursor, and the hex color code. It's rendered as a separate OpenGL pass on top of the screenshot, using blending with `GL_SRC_ALPHA` and `GL_ONE_MINUS_SRC_ALPHA`.

For font rendering, I use stb_truetype.h from Sean Barrett's single-header library collection. It's public domain and it's one file, so I just bundle it in the source tree. The `try_init_truetype` function tries to find a TrueType font on the system:

1. If the config specifies a full path with a `/`, try that directly
2. If the config specifies a font name (like `DejaVuSans`), search through font directories recursively
3. Try hardcoded known paths like `/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf`
4. If all TrueType attempts fail, fall back to the built-in 8x8 bitmap font from `font8x8.h`

The font search walks directories using an explicit stack (a fixed-size array with 64 entries, used as a stack) instead of recursion. This avoids stack overflow on deeply nested font directories. It matches font names case-insensitively against `.ttf` and `.otf` files.

The bitmap fallback is 128 characters, 8 bytes per character, with each byte representing a row of 8 pixels. It looks blocky and ugly, but it's always there. No font file = no crash.

### The Color Picker

The OSD also shows the RGB values and hex code of whatever pixel is under the cursor. My first version read from the OpenGL framebuffer using `glReadPixels`, but that gives you the post-shader color. If you had the CRT shader active, the color picker would show the CRT-ized color, not the actual pixel. That's wrong.

The fix was reading from the source XImage data directly. Since I already have the pixel data in memory from the screenshot capture, I just index into it using the cursor position transformed to screenshot coordinates:

```c
int bpp = image->bits_per_pixel / 8;
int row = screenshot_y * image->bytes_per_line;
unsigned char *pixel = (unsigned char*)image->data + row + screenshot_x * bpp;
```

The transformation from screen coordinates to screenshot coordinates is handled by `screen_to_screenshot()` in `navigation.c`, which accounts for the camera position, zoom level, and aspect ratio correction. The result is the exact pixel value from the original screenshot, unaffected by whatever shader is running.

## The PNG Writer

When you press `s`, cboomer saves the current view to a PNG file. I didn't want to depend on libpng for one feature, so I wrote a PNG encoder from scratch. It's about 50 lines of code and produces valid PNG files that open in any image viewer.

The PNG format is surprisingly approachable for a simple encoder. You write an 8-byte signature, then a series of chunks. Each chunk has a 4-byte length, a 4-byte type, the data, and a 4-byte CRC32. I only need three chunk types: IHDR (image header), IDAT (pixel data), and IEND (end marker).

The pixel data needs to be filtered before compression. PNG supports five filter types per row. I use filter type 0 (None), which means each row is stored as-is with a leading zero byte. This is the simplest option, and zlib's compression handles it fine:

```c
unsigned char raw_row[width * 3 + 1];
for (int y = 0; y < height; y++) {
    raw_row[0] = 0; // filter type None
    for (int x = 0; x < width; x++) {
        // BGRA to RGB conversion
        raw_row[x * 3 + 1] = pixel[y * width + x].r;
        raw_row[x * 3 + 2] = pixel[y * width + x].g;
        raw_row[x * 3 + 3] = pixel[y * width + x].b;
    }
    // append raw_row to the uncompressed data buffer
}

compress2(dest, &dest_len, raw_data, raw_data_len, Z_BEST_COMPRESSION);
// write IDAT chunk with dest
```

This is a proper PNG encoder. It's not the most efficient (no interlacing, no palette, no Adam7), but it produces valid files. I also wrote a PPM encoder (`save_to_ppm`) for when I just need a quick dump - PPM is even simpler, just a header followed by raw RGB bytes.

## The Build System

The Makefile uses a pattern I haven't seen in many other projects: stacked targets. Instead of having separate targets for each build configuration, you combine them on the command line:

```console
$ make dev live mitshm
```

Each word in `MAKECMDGOALS` is checked and adds the corresponding `-D` flag. The targets are phony and depend on the binary, so they just add flags and trigger the build:

```makefile
ifneq ($(filter dev,$(MAKECMDGOALS)),)
CFLAGS += -DDEVELOPER
endif
ifneq ($(filter live,$(MAKECMDGOALS)),)
CFLAGS += -DLIVE
endif
ifneq ($(filter mitshm,$(MAKECMDGOALS)),)
CFLAGS += -DMITSHM
endif
```

There's a quirk: `make clean dev` will also add `-DDEVELOPER` because `clean` appears in `MAKECMDGOALS` but doesn't stop the filter from also matching `dev`. The build works fine (the binary gets rebuilt with `-DDEVELOPER`), but then `clean` runs and removes it. I've been meaning to fix this but it's never annoyed me enough to actually do it.

The git hash is baked into the binary at build time:

```makefile
GIT_HASH := $(shell git rev-parse HEAD 2>/dev/null || echo unknown)
CFLAGS += -DGIT_HASH=\"$(GIT_HASH)\"
```

This means you can run `cboomer --version` (or check the binary's strings) and know exactly which commit it was built from. The `\"` quoting is important - it tells the shell to pass the literal quotes to the compiler, so the preprocessor sees `-DGIT_HASH="abc123def"` and produces a string constant.

## Bugs I Hit Along The Way

### The Color Picker Bug

I already mentioned this, but it's worth repeating because it's a good lesson: if you're building a color picker on top of a rendering pipeline that applies visual effects, read the source data, not the framebuffer. The framebuffer has been through the shader. The source data is what you actually want.

### Rotation Was Harder Than It Needed to Be

When I first added rotation (Ctrl+[ and Ctrl+] to rotate the view 90 degrees), I started writing a rotation matrix. I was about ten lines in when I realized that rotating a screenshot by 90 degrees is just a remapping of the texture coordinates. The four vertices of the fullscreen quad each have a UV coordinate. Rotating by 90 degrees means vertex 0 gets vertex 1's UV, vertex 1 gets vertex 2's UV, and so on:

```c
int src = (i + rotation) % 4;
verts[i*4+2] = base_u[src];
verts[i*4+3] = base_v[src];
```

Four lines. No `sin`, no `cos`, no matrix multiplication. I felt silly for reaching for the rotation matrix first, but I also felt smart for realizing it was unnecessary.

### PPM Writer Integer Overflow

The PPM writer had an integer overflow bug. I was using `unsigned int` for the pixel count, which is more than enough for the pixel count itself (33 million on 8K fits in 32 bits). But the output buffer size is `width * height * 3` (for RGB), and on a large display that multiplication can overflow 32 bits before you assign it to a pointer-sized variable. The fix was using `unsigned long` for the intermediate calculation.

### The X11 Grab Problem

The `select` build variant uses `XGrabPointer` and `XGrabKeyboard` to capture input so the user can click on a window to select it. The grab is aggressive - it prevents any other window from receiving input while the grab is active. If cboomer crashes while the grab is active, your keyboard and mouse are effectively captured by a dead process. You have to switch to a TTY with Ctrl+Alt+F1 and kill the process manually.

I haven't fixed this yet, but the solution is either a signal handler (catch SIGSEGV/SIGABRT and release the grabs) or a timeout (if the user doesn't select a window within N seconds, release the grab and exit).

## What I'd Do Differently Now

The vertex shader receives the camera position and scale as separate uniforms and does the transformation in the vertex shader. A better approach would be to compute a combined model-view-projection matrix on the CPU and pass that as a single uniform. It would be cleaner and it would let me move the aspect-ratio correction into the shader instead of baking it into the vertex positions on the CPU side.

The OSD font search is functional but fragile. The explicit stack approach works on every Linux system I've tried, but a deeply nested font directory or a symlink loop would break it. Using `nftw()` (file tree walk, POSIX) would be more robust, but I wanted to avoid introducing another dependency for something that works 99% of the time.

The color depth is assumed to be 32 bits per pixel (8 bits per channel, BGRA order). This is true on every modern X11 setup, but it's not guaranteed by the protocol. A more robust implementation would check the actual visual depth and adjust the pixel format accordingly.

And finally, the build system could generate the shader header as a Makefile rule with proper dependency tracking instead of always regenerating it. But the shader generation script runs in under 100ms, so it's never been a bottleneck.

## Why This Project Exists

I started this because I wanted to understand how X11 and OpenGL work together. Creating a GLX context requires picking a visual, creating a window with that visual, and then creating an OpenGL context from that window's GLX binding. Getting all of those steps right without following a tutorial was the goal.

Every feature I added taught me something. The MIT-SHM path taught me about X11 extensions and shared memory. The shader system taught me about GLSL program lifecycle management. The PNG writer taught me the binary format well enough that I could explain it to someone else without looking it up. The camera system taught me about frame-rate independent physics.

The source is on GitHub if you want to look at any of this in more detail. It's about 1,900 lines of C11 across 6 source files, plus 400 lines of GLSL across 15 shaders, a handful of headers, and the bundled `stb_truetype.h`. The Makefile has a `help` target that explains all the build variants, and `TODO.md` has notes about porting to Wayland and Windows if that's something you'd want to work on.
