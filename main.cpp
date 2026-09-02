#include <string>
#include <iostream>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>
#include <cstring>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <poll.h>

#include "string_helpers/string_helpers.h"
#include "graphics/graphics.h"
#include "desktop/desktop.h"
#include "component/box/box.h"
#include "mouse/mouse.h"


using namespace std;

int main(int argc, char* argv[]) {
    cout << "Welcome to Custom OS" << endl;
    cout << "os: starting boot graphics" << endl;

    const auto background = 0xFF00000F;

    Graphics* g = new Graphics(800, 600, background);

    Desktop* desktop = new Desktop(g->width(), g->height(), background, g);


    Window* box1 = new Window({100, 100}, {300, 300});
    desktop->addWindow(dynamic_cast<Window*>(box1));

    Mouse* mouse = new Mouse(desktop, 800, 600);
    mouse->setViewportSize(g->width(), g->height());

    while (true) {
        try {
            mouse->readMouse();
            break;
        } catch (const std::exception &e) {
            std::cerr << "Exception caught while reading mouse: " << e.what() << std::endl;
            // Wait
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
    }

    while (true) {
        try {
            mouse->readMouse();
        } catch (const std::exception &e) {
            std::cerr << "Exception caught while reading mouse: " << e.what() << std::endl;
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
    }
    
    cout << "os: exiting shell" << endl;

    delete desktop;
    delete box1;
    delete mouse;

    return 0; //EXIT_STATUS;
}
