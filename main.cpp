#include <string>
#include <iostream>
#include <sys/wait.h>
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
#include "component/Desktop/Desktop.h"


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

    Graphics g{800, 600, 0x00FFFFFF};

    g.drawRectBuffer({0, 0}, {200, 200}, 0x00FF00FF);
    g.drawScreen();

    Desktop* desktop = new Desktop({0, 0}, {800, 600}, 0x00FFFFFF);
    g.addComponent(desktop);
    g.drawComponents();

    cout << "os: entering shell" << endl;

    os_loop();

    return 0; //EXIT_STATUS;
}
