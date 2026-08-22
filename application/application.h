#pragma once

#include "../component/screen/screen.h"
#include <vector>

class Application {
    std::vector<Screen*> screens;
    
public:
    Application() {}
    void addScreen(Screen* screen);
};
