
#include <iostream>
#include <vector>
#include <cmath>
#include <chrono>
#include <cstdlib>

double processArray(const std::vector<double>& data) {
    double result = 0.0;

    for (std::size_t i = 0; i < data.size(); ++i) {
        result += std::sqrt(data[i]) * 1.5;
    }

    return result;
}

int main(int argc, char* argv[]) {
    const std::size_t N = 1000000;
    const int iterations = (argc > 1) ? std::atoi(argv[1]) : 1000;

    std::vector<double> data(N);

    for (std::size_t i = 0; i < N; ++i) {
        data[i] = static_cast<double>(i + 1);
    }

    auto start = std::chrono::steady_clock::now();

    double result = 0.0;

    for (int i = 0; i < iterations; ++i) {
        result += processArray(data);
    }

    auto end = std::chrono::steady_clock::now();

    std::chrono::duration<double> elapsed = end - start;

    std::cout << "Result: " << result << '\n';
    std::cout << "Execution time: " << elapsed.count()
              << " seconds\n";

    return 0;
}
