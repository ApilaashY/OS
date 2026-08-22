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
        mouse->readMouse();
        // std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }

    cout << "os: entering shell" << endl;

    os_loop();

    delete desktop;
    delete box1;
    delete mouse;

    return 0; //EXIT_STATUS;
}
