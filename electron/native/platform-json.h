#pragma once
#include <string>
static std::string jsonString(const std::string &value) {
    std::string result = "\"";
    for (unsigned char ch : value) {
        if (ch == '\\' || ch == '"') { result += '\\'; result += ch; }
        else if (ch >= 32) result += ch;
    }
    return result + '"';
}
