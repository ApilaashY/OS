#include <string>
#include <sstream>
#include <iostream>

#include "string_helpers.h"

std::string os_readline() {
    std::string line;
    std::getline(std::cin, line);
    return line;
}

std::string* os_split(std::string line) {
    std::stringstream s(line);
    std::string* args = new std::string[10]; // max 10 arguments
    int i = 0;
    while (s >> args[i]) {
        i++;
    }
    args[i] = ""; // sentinel
    return args;
}