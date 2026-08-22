#pragma once

#include "../desktop/desktop.h"

class Mouse {
    Desktop* desktop;
    int fd = -1;
    int x_position = 0;
    int y_position = 0;
    int viewport_width = 800;
    int viewport_height = 600;
    int x_min = 0;
    int x_max = 65535;
    int y_min = 0;
    int y_max = 65535;
    bool left_button = false;
    bool right_button = false;
    bool received_event = false;

public:
    explicit Mouse(Desktop* desktop, int viewport_width = 800, int viewport_height = 600)
        : desktop(desktop), viewport_width(viewport_width), viewport_height(viewport_height) {}
    void setViewportSize(int width, int height);
    ~Mouse();
    void readMouse();

    int x() const { return x_position; }
    int y() const { return y_position; }
    bool leftPressed() const { return left_button; }
    bool rightPressed() const { return right_button; }
};
