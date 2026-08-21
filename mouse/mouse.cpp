#include "./mouse.h"

#include <algorithm>
#include <cerrno>
#include <cctype>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <linux/input.h>
#include <poll.h>
#include <stdexcept>
#include <string>
#include <sys/ioctl.h>
#include <unistd.h>

namespace {
// Try to open a Linux input device that represents a mouse.
// In modern Linux systems this is usually /dev/input/eventX.
int openMouseDevice() {
    static constexpr const char* candidates[] = {
        "/dev/input/mice",
        "/dev/input/event0",
        "/dev/input/event1",
        "/dev/input/event2",
        "/dev/input/event3",
        "/dev/input/event4",
        "/dev/input/event5",
        "/dev/input/event6",
        "/dev/input/event7",
        "/dev/input/event8",
        "/dev/input/event9",
        "/dev/input/event10",
        "/dev/input/event11",
        "/dev/input/event12",
        "/dev/input/event13",
        "/dev/input/event14",
        "/dev/input/event15",
        nullptr,
    };

    int best_fd = -1;
    int best_score = -1;

    for (const char* const* path = candidates; *path != nullptr; ++path) {
        std::cout << "[mouse] probing " << *path << std::endl;
        int candidate_fd = open(*path, O_RDONLY | O_NONBLOCK);
        if (candidate_fd < 0) {
            std::cout << "[mouse] failed to open " << *path << ": " << std::strerror(errno) << std::endl;
            continue;
        }

        char name[256]{};
        if (ioctl(candidate_fd, EVIOCGNAME(sizeof(name) - 1), name) >= 0) {
            std::cout << "[mouse] candidate " << *path << " -> " << name << std::endl;
        } else {
            std::cout << "[mouse] candidate " << *path << " -> name unavailable" << std::endl;
        }

        std::string device_name{name};
        std::transform(device_name.begin(), device_name.end(), device_name.begin(), [](unsigned char c) {
            return static_cast<char>(std::tolower(c));
        });

        int score = 0;
        if (device_name.find("tablet") != std::string::npos || device_name.find("usb") != std::string::npos) {
            score += 4;
        }
        if (device_name.find("mouse") != std::string::npos) {
            score += 2;
        }
        if (device_name.find("touchpad") != std::string::npos) {
            score += 2;
        }
        if (device_name.find("power button") != std::string::npos || device_name.find("keyboard") != std::string::npos) {
            score -= 5;
        }

        if (score > best_score) {
            best_score = score;
            best_fd = candidate_fd;
        } else {
            close(candidate_fd);
        }
    }

    if (best_fd >= 0) {
        std::cout << "[mouse] selected fd " << best_fd << std::endl;
        return best_fd;
    }

    return -1;
}
}  // namespace

Mouse::~Mouse() {
    if (fd >= 0) {
        close(fd);
    }
}

void Mouse::setViewportSize(int width, int height) {
    viewport_width = width;
    viewport_height = height;
}

void Mouse::readMouse() {
    if (fd < 0) {
        fd = openMouseDevice();
        if (fd < 0) {
            std::cerr << "mouse: no usable mouse device found" << '\n';
            return;
        }

        struct input_absinfo absinfo{};
        if (ioctl(fd, EVIOCGABS(ABS_X), &absinfo) == 0) {
            x_min = absinfo.minimum;
            x_max = absinfo.maximum;
        }
        if (ioctl(fd, EVIOCGABS(ABS_Y), &absinfo) == 0) {
            y_min = absinfo.minimum;
            y_max = absinfo.maximum;
        }
    }

    pollfd pfd{};
    pfd.fd = fd;
    pfd.events = POLLIN;
    int ready = poll(&pfd, 1, 1000);
    if (ready < 0) {
        std::cerr << "mouse: poll failed: " << std::strerror(errno) << '\n';
        throw std::runtime_error("Failed to poll mouse input event");
    }
    if (ready == 0) {
        return;
    }

    while (true) {
        struct input_event event {};
        ssize_t bytesRead = read(fd, &event, sizeof(event));
        if (bytesRead < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                break;
            }
            std::cerr << "mouse: read failed: " << std::strerror(errno) << '\n';
            throw std::runtime_error("Failed to read mouse input event");
        }
        if (bytesRead != sizeof(event)) {
            std::cerr << "mouse: short read: " << bytesRead << " bytes" << '\n';
            break;
        }

        std::cout << "[mouse] event type=" << event.type
                  << " code=" << event.code
                  << " value=" << event.value << std::endl;

        if (event.type == EV_REL) {
            if (event.code == REL_X) {
                x_position += event.value * 4;
            } else if (event.code == REL_Y) {
                y_position -= event.value * 4;
            }
        } else if (event.type == EV_ABS) {
            if (event.code == ABS_X) {
                const int range = std::max(1, x_max - x_min);
                x_position = std::clamp((event.value - x_min) * viewport_width / range, 0, viewport_width - 1);
            } else if (event.code == ABS_Y) {
                const int range = std::max(1, y_max - y_min);
                y_position = std::clamp((event.value - y_min) * viewport_height / range, 0, viewport_height - 1);
            }
        }
    }

    std::cout << "mouse: x=" << x_position << " y=" << y_position
              << " left=" << left_button << " right=" << right_button << '\n';

    desktop->drawMouse({x_position, y_position});
}
