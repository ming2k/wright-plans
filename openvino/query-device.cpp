#include <openvino/openvino.hpp>

#include <exception>
#include <iostream>

int main() {
    try {
        ov::Core core;
        for (const auto & device : core.get_available_devices()) {
            std::cout << device << '\n';
        }
    } catch (const std::exception & error) {
        std::cerr << "OpenVINO device query failed: " << error.what() << '\n';
        return 1;
    }

    return 0;
}
