#include <string>
#include <iostream>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <poll.h>

// Only include DRM headers if we're building for kernel (not userspace)
#ifndef NO_DRM_HEADERS
#include <drm/drm.h>
#include <drm/drm_mode.h>
#endif

#include "string_helpers/string_helpers.h"

using namespace std;


// -----------------------------------------------------------------------------
// os_show_boot_pixels()
//
// Talk to the Linux Direct Rendering Manager (DRM) to put a picture on the
// screen. This is the same subsystem X11, Wayland, and console text-mode use
// under the hood.
//
// The vocabulary you'll see below (borrowed straight from real GPU hardware):
//
//   Connector   - a physical output port (HDMI-1, VGA-1, our virtual "Virtual-1"
//                 under QEMU). Answers "is a monitor plugged in?" and "what
//                 resolutions can it do?".
//   Mode        - a resolution/refresh-rate combo the connector accepts, e.g.
//                 1280x800 @ 60 Hz. Every connector exposes a list of modes;
//                 the first one is normally the preferred/native one.
//   Encoder     - the internal signal converter that turns pixels into
//                 whatever wire format the connector needs.
//   CRTC        - "Cathode Ray Tube Controller" (name is historical). The
//                 scan-out engine: it walks through a framebuffer in memory,
//                 pixel by pixel, at pixel-clock rate, and streams the data
//                 out through an encoder to a connector. One CRTC = one output
//                 being driven.
//   Dumb buffer - a chunk of "just memory" that the kernel gives us. Both the
//                 CPU (through mmap) and the display engine can access it.
//                 Called "dumb" because it doesn't need GPU-specific magic;
//                 you literally poke bytes into it.
//   Framebuffer - a DRM object wrapping a dumb buffer with metadata (width,
//                 height, pitch, pixel format) so the CRTC knows how to
//                 interpret those bytes.
//
// The overall pipeline we build here:
//
//     [our pixels in RAM] -> Framebuffer -> CRTC -> Encoder -> Connector -> monitor
//
// Every call below is one ioctl() on /dev/dri/card0. An ioctl is just "call a
// kernel function through the driver by number, passing a struct". We use the
// raw kernel UAPI headers from <drm/*.h> — no libdrm required.
//
// The function is best-effort: any failure logs to stderr (which goes to the
// serial console because we run as PID 1) and returns, so the shell always
// starts.
// -----------------------------------------------------------------------------
static void os_show_boot_pixels() {
    // ---- Step 0: make sure the device node exists -------------------------
    // In a normal Linux install, udev populates /dev at boot. Our initramfs
    // is stripped down and has no udev, so /dev/dri/card0 wouldn't exist. We
    // ask the kernel to mount its built-in "devtmpfs" onto /dev; that
    // filesystem is auto-populated with a node for every device the kernel
    // knows about, including our GPU. If it's already mounted (kernel config
    // CONFIG_DEVTMPFS_MOUNT=y does it automatically) this returns an error
    // that we happily ignore.
    mount("devtmpfs", "/dev", "devtmpfs", 0, nullptr);

    // ---- Step 1: open the DRM device --------------------------------------
    // /dev/dri/card0 is the "primary" DRM node for our GPU (card1, card2, ...
    // exist if you have multiple GPUs). Opening it read-write is what makes
    // the ioctls below work. The first process to open it becomes the "DRM
    // master" and is the only one allowed to do mode-setting — since we're
    // PID 1 in an initramfs, nobody's competing.
    // O_CLOEXEC is a hygiene flag: any child we spawn later won't inherit fd.
    int fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        perror("open /dev/dri/card0");
        return;
    }

    // ---- Step 2: list the display resources -------------------------------
    // GETRESOURCES tells us how many connectors, CRTCs, encoders, and existing
    // framebuffers the driver has, and gives us their integer IDs.
    //
    // The DRM UAPI uses a "two-pass" pattern for anything with a variable-
    // sized list:
    //   1. Call once with count fields zero and pointers null -> kernel fills
    //      in the counts but doesn't write anywhere.
    //   2. Allocate arrays of the right size, put their addresses in the
    //      ptr fields, and call again -> kernel fills the arrays.
    // This lets user-space allocate exactly the right amount of memory.
    drm_mode_card_res res{};
    if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res) < 0) {
        perror("DRM_IOCTL_MODE_GETRESOURCES (sizes)");
        close(fd);
        return;
    }

    // Allocate buffers to receive the IDs.
    vector<uint32_t> fb_ids(res.count_fbs);
    vector<uint32_t> crtc_ids(res.count_crtcs);
    vector<uint32_t> connector_ids(res.count_connectors);
    vector<uint32_t> encoder_ids(res.count_encoders);

    // The struct's pointer fields are __u64 because a 32-bit user-space
    // process might talk to a 64-bit kernel. We stuff regular pointers in
    // there by casting to uint64_t.
    res.fb_id_ptr        = reinterpret_cast<uint64_t>(fb_ids.data());
    res.crtc_id_ptr      = reinterpret_cast<uint64_t>(crtc_ids.data());
    res.connector_id_ptr = reinterpret_cast<uint64_t>(connector_ids.data());
    res.encoder_id_ptr   = reinterpret_cast<uint64_t>(encoder_ids.data());

    // Second pass — the kernel now writes IDs into the arrays.
    if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res) < 0) {
        perror("DRM_IOCTL_MODE_GETRESOURCES (fill)");
        close(fd);
        return;
    }

    uint32_t h_offset = 0;
    uint32_t v_offset = 0;

    // ---- Step 3: find something we can actually display on ----------------
    // Walk every connector and pick the first one that (a) has a monitor
    // plugged in and (b) advertises at least one mode. Under QEMU with -vga
    // std there's exactly one connector ("Virtual-1") that's always connected.
    for (uint32_t cid : connector_ids) {
        // Same two-pass pattern: first get counts for this connector's own
        // sub-arrays (its modes, its compatible encoders, and any properties
        // set on it).
        drm_mode_get_connector conn{};
        conn.connector_id = cid;
        if (ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &conn) < 0) continue;

        vector<drm_mode_modeinfo> modes(conn.count_modes);
        vector<uint32_t> encs(conn.count_encoders);
        vector<uint32_t> props(conn.count_props);
        vector<uint64_t> prop_vals(conn.count_props);

        conn.modes_ptr       = reinterpret_cast<uint64_t>(modes.data());
        conn.encoders_ptr    = reinterpret_cast<uint64_t>(encs.data());
        conn.props_ptr       = reinterpret_cast<uint64_t>(props.data());
        conn.prop_values_ptr = reinterpret_cast<uint64_t>(prop_vals.data());

        // Second pass — arrays now filled in.
        if (ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &conn) < 0) continue;

        // conn.connection is an enum: 1 = connected, 2 = disconnected,
        // 3 = unknown. Skip anything that isn't literally connected, or that
        // has no modes we could set.
        if (conn.connection != 1 /* DRM_MODE_CONNECTED */) continue;
        if (conn.count_modes == 0) continue;

        // Modes are sorted preferred-first. modes[0] is what a normal display
        // manager would pick — the monitor's native resolution. Under our
        // QEMU stdvga this is 1280x800.
        drm_mode_modeinfo mode = modes[0];

        // ---- Step 4: pick a CRTC to drive this connector ------------------
        // A CRTC (scan-out engine) doesn't belong to a specific output — the
        // "encoder" is what wires a CRTC to a connector. Fastest path: if the
        // connector already has an encoder attached (from the previous boot,
        // or by the driver's default), and that encoder is already bound to a
        // CRTC, just reuse it.
        uint32_t crtc_id = 0;
        if (conn.encoder_id) {
            drm_mode_get_encoder e{};
            e.encoder_id = conn.encoder_id;
            if (ioctl(fd, DRM_IOCTL_MODE_GETENCODER, &e) == 0 && e.crtc_id) {
                crtc_id = e.crtc_id;
            }
        }
        // Fallback: no encoder is currently bound. Iterate every encoder this
        // connector *could* use and pick the first CRTC that encoder allows.
        // "possible_crtcs" is a bitmask where bit i means "I can drive the
        // i-th CRTC from the resources list".
        if (!crtc_id) {
            for (uint32_t eid : encs) {
                drm_mode_get_encoder e{};
                e.encoder_id = eid;
                if (ioctl(fd, DRM_IOCTL_MODE_GETENCODER, &e) < 0) continue;
                for (size_t i = 0; i < crtc_ids.size(); ++i) {
                    if (e.possible_crtcs & (1u << i)) { crtc_id = crtc_ids[i]; break; }
                }
                if (crtc_id) break;
            }
        }
        if (!crtc_id) continue;

        // ---- Step 5 + 6 + 7: allocate TWO buffers (double buffering) ------
        // To avoid tearing we need a "front" buffer (the CRTC is currently
        // scanning it out) and a "back" buffer (safe for us to draw into).
        // Then we swap them at vsync via PAGE_FLIP.
        //
        // Each buffer needs the whole stack from Steps 5/6/7 in the
        // single-buffer version:
        //   CREATE_DUMB -> handle       (chunk of pixel memory)
        //   ADDFB       -> fb_id        (scanout-ready framebuffer object)
        //   MAP_DUMB    -> mmap offset  (cookie for mmap)
        //   mmap        -> void* pixels (CPU pointer we can write through)
        struct Buf {
            uint32_t handle;
            uint32_t pitch;
            uint64_t size;
            uint32_t fb_id;
            void*    pixels;
        };
        Buf bufs[2] = {};
        bool alloc_ok = true;
        for (int i = 0; i < 2; ++i) {
            drm_mode_create_dumb create{};
            create.width  = mode.hdisplay;
            create.height = mode.vdisplay;
            create.bpp    = 32;
            if (ioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &create) < 0) {
                perror("DRM_IOCTL_MODE_CREATE_DUMB");
                alloc_ok = false; break;
            }
            bufs[i].handle = create.handle;
            bufs[i].pitch  = create.pitch;
            bufs[i].size   = create.size;

            drm_mode_fb_cmd fb{};
            fb.width  = create.width;
            fb.height = create.height;
            fb.pitch  = create.pitch;
            fb.bpp    = 32;
            fb.depth  = 24;
            fb.handle = create.handle;
            if (ioctl(fd, DRM_IOCTL_MODE_ADDFB, &fb) < 0) {
                perror("DRM_IOCTL_MODE_ADDFB");
                alloc_ok = false; break;
            }
            bufs[i].fb_id = fb.fb_id;

            drm_mode_map_dumb map{};
            map.handle = create.handle;
            if (ioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &map) < 0) {
                perror("DRM_IOCTL_MODE_MAP_DUMB");
                alloc_ok = false; break;
            }
            bufs[i].pixels = mmap(nullptr, create.size,
                                  PROT_READ | PROT_WRITE, MAP_SHARED,
                                  fd, map.offset);
            if (bufs[i].pixels == MAP_FAILED) {
                perror("mmap");
                alloc_ok = false; break;
            }
        }
        if (!alloc_ok) continue;

        // Pre-clear both buffers so no random garbage flashes on first flip.
        memset(bufs[0].pixels, 0, bufs[0].size);
        memset(bufs[1].pixels, 0, bufs[1].size);

        // ---- Step 8: turn the display on ("mode-set") ---------------------
        // Same as before — hand the CRTC the FIRST buffer as its initial
        // front. From this moment the display is scanning bufs[0].
        uint32_t connector_for_setcrtc = cid;
        drm_mode_crtc sc{};
        sc.set_connectors_ptr = reinterpret_cast<uint64_t>(&connector_for_setcrtc);
        sc.count_connectors   = 1;
        sc.crtc_id            = crtc_id;
        sc.fb_id              = bufs[0].fb_id;
        sc.mode               = mode;
        sc.mode_valid         = 1;
        if (ioctl(fd, DRM_IOCTL_MODE_SETCRTC, &sc) < 0) {
            perror("DRM_IOCTL_MODE_SETCRTC");
            continue;
        }

        // ---- Step 9: animation loop, vsync-flipped + capped at 60 fps -----
        // The scan-out engine is currently reading from bufs[0]. That means
        // bufs[1] is safe to draw into (the "back" buffer). When we're done
        // drawing a frame we ask DRM to swap them at the next vsync via
        // PAGE_FLIP.
        //
        // The read() below waits for the flip-complete event. On real
        // hardware that's naturally paced by the monitor's refresh rate. On
        // QEMU bochs there's no real vsync — the driver fires the event
        // almost immediately, so without an extra cap this loop would spin
        // at thousands of fps and burn CPU for no visible benefit.
        //
        // To cap at 60 fps we use clock_nanosleep with TIMER_ABSTIME. Every
        // frame we advance a "next_frame" deadline by 1/60 s and sleep until
        // that absolute moment. If a frame runs long, the next sleep is
        // shorter (or skipped entirely) — no drift accumulates over time.
        constexpr long FRAME_NS = 1'000'000'000L / 60;   // ~16.67 ms per frame

        timespec next_frame{};
        clock_gettime(CLOCK_MONOTONIC, &next_frame);

        int back = 1;                       // buf[0] is on screen; draw into buf[1]
        // Keep the boot animation visible long enough to be clearly seen in
        // QEMU before control returns to the shell.
        constexpr int BOOT_ANIM_FRAMES = 36000; // ~10 minutes at 60 fps
        for (int frame = 0; frame < BOOT_ANIM_FRAMES; ++frame) {
            Buf& b = bufs[back];

            // --- clear + draw the moving 70x70 square ---
            // XRGB8888: 0x00000000 = black, 0x00FFFFFF = white.
            // Row addressing uses pitch, not width*4.
            memset(b.pixels, 0, b.size);
            uint8_t* base = static_cast<uint8_t*>(b.pixels);
            for (uint32_t y = 0; y < 70 && y < mode.vdisplay; ++y) {
                if (y + v_offset >= mode.vdisplay) continue;

                uint32_t* row = reinterpret_cast<uint32_t*>(base + (y + v_offset) * b.pitch);
                uint32_t* next_row = reinterpret_cast<uint32_t*>(base + ((y + v_offset + 70)%mode.vdisplay) * b.pitch);
                for (uint32_t x = 0; x < 70 && x < mode.hdisplay; ++x) {
                    if (x + h_offset >= mode.hdisplay) {
                        next_row[x + h_offset - mode.hdisplay] = 0x00FFFFFFu;
                    } else row[x + h_offset] = 0x00FFFFFFu;
                }
            }

            // Advance for the NEXT frame. 8 px per frame at 60 fps -> 480 px/s.
            h_offset += 8;
            if (h_offset > mode.hdisplay) {
                h_offset = 0;
                v_offset += 70;
                if (v_offset > mode.vdisplay) v_offset = 0;
            }

            // --- queue the swap ---
            // PAGE_FLIP asks the CRTC to atomically switch to a new fb_id
            // during the next vertical blanking interval (between two frames
            // being scanned out). Because the switch is atomic and happens
            // between frames, the monitor NEVER sees a half-updated buffer —
            // that's what kills tearing.
            //
            // DRM_MODE_PAGE_FLIP_EVENT tells the kernel: after the flip
            // actually completes, deliver an event on the drm fd so we know
            // it's safe to reuse the OTHER buffer.
            drm_mode_crtc_page_flip flip{};
            flip.crtc_id = crtc_id;
            flip.fb_id   = b.fb_id;
            flip.flags   = DRM_MODE_PAGE_FLIP_EVENT;
            if (ioctl(fd, DRM_IOCTL_MODE_PAGE_FLIP, &flip) < 0) {
                perror("DRM_IOCTL_MODE_PAGE_FLIP");
                break;
            }

            // --- drain the flip-complete event ---
            // Some virtual GPUs/drivers may not deliver flip events reliably.
            // Do not block forever waiting for one; if no event arrives
            // promptly, stop the animation and continue booting to the shell.
            pollfd pfd{};
            pfd.fd = fd;
            pfd.events = POLLIN;
            int pr = poll(&pfd, 1, 100);
            if (pr <= 0) {
                cerr << "os: DRM flip event timeout, continuing boot\n";
                break;
            }

            char evbuf[128];
            ssize_t n = read(fd, evbuf, sizeof(evbuf));
            if (n <= 0) {
                cerr << "os: DRM flip event read failed, continuing boot\n";
                break;
            }

            // Swap: the buffer we just showed becomes the front; we draw the
            // next frame into the one that WAS the front.
            back ^= 1;

            // --- pace to 60 fps ---
            // Bump the deadline by one frame period. Normalise the timespec
            // so tv_nsec stays in [0, 1e9). Then sleep until that absolute
            // moment on the same clock we sampled from. If we've already
            // missed the deadline (frame ran long), clock_nanosleep returns
            // immediately.
            next_frame.tv_nsec += FRAME_NS;
            if (next_frame.tv_nsec >= 1'000'000'000L) {
                next_frame.tv_sec  += 1;
                next_frame.tv_nsec -= 1'000'000'000L;
            }
            clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &next_frame, nullptr);
        }

        close(fd);
        return;
    }

    // We tried every connector and none were usable.
    cerr << "os: no usable DRM connector found\n";
    close(fd);
}


// Built in functions:
int os_cd(string *args);
int os_help(string *args);
int os_exit(string *args);

/*
  List of builtin commands, followed by their corresponding functions.
 */
string builtin_str[] = {
  "cd",
  "help",
  "exit"
};

int (*builtin_func[]) (string *) = {
  &os_cd,
  &os_help,
  &os_exit
};

int os_cd(string *args) {
    if (args[1].empty()) {
        cerr << "os: expected argument to \"cd\"\n";
    } else {
        if (chdir(args[1].c_str()) != 0) {
            perror("os");
        }
    }
    return 1;
}

int os_help(string *args) {
    cout << "Custom OS" << endl;
    cout << "Type program names and arguments, and hit enter." << endl;
    cout << "The following are built in:" << endl;

    for (int i = 0; i < sizeof(builtin_str) / sizeof(string); i++) {
        cout << "  " << builtin_str[i] << endl;
    }

    cout << "Use the man command for information on other programs.";
    return 1;
}

int os_exit(string *args) {
    cout << "Exiting Custom OS..." << endl;
    return 0;
}



int os_launch(string *args) {
    int status = 1;
    pid_t pid = fork();

    if (pid < 0) {
        perror("Fork failed");
        return 1;
    } else if (pid == 0) {
        // Child process
        char *argv[11];
        int i = 0;
        while (!args[i].empty() && i < 10) {
            argv[i] = args[i].data();
            i++;
        }
        argv[i] = nullptr;

        if (execvp(argv[0], argv) < 0) {
            perror("Exec failed");
        }
        exit(EXIT_FAILURE);
    } else {
        // Parent process
        do {
            waitpid(pid, &status, WUNTRACED);
        } while (!WIFEXITED(status) && !WIFSIGNALED(status));
    }

    return 1;
}


// Execute function
int os_execute(string *args) {
    if (args[0].empty()) {
        return 1;
    }

    for (int i = 0; i < sizeof(builtin_str) / sizeof(string); i++) {
        if (args[0] == builtin_str[i]) {
            return (*builtin_func[i])(args);
        }
    }

    int status = os_launch(args);

    return status;
}

// Main Loop
void os_loop() {
    int status;
    do {
        cout << "os> ";
        string line = os_readline();
        string *args = os_split(line);
        status = os_execute(args);
    } while (status);
}

int main(int argc, char* argv[]) {
    cout << "Welcome to Custom OS" << endl;
    cout << "os: starting boot graphics" << endl;

    os_show_boot_pixels();

    cout << "os: entering shell" << endl;

    os_loop();

    return 0; //EXIT_STATUS;
}
