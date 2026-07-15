module; // Starts the Global Module Fragment

#include <string> // Includes must go here

export module string_helpers; // Starts the module purview

export std::string os_readline();
export std::string* os_split(std::string line);