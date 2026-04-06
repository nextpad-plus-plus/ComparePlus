/*
 * This file is part of ComparePlus plugin for Notepad++ (macOS port)
 * Copyright (C) 2016-2025 Pavel Nedev (pg.nedev@gmail.com)
 *
 * macOS port by Andrey Letov, 2026
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

#pragma once

#include <cstdint>
#include <string>
#include <vector>
#include <fstream>
#include <functional>
#include <sys/stat.h>


// =====================================================================
//  ScopedIncrementer — RAII integer counter
// =====================================================================

template <typename T>
struct ScopedIncrementer
{
    ScopedIncrementer(T& useCount) : _useCount(useCount) { ++_useCount; }
    ~ScopedIncrementer() { --_useCount; }

    ScopedIncrementer& operator=(const ScopedIncrementer&) = delete;

private:
    T& _useCount;
};

using ScopedIncrementerInt = ScopedIncrementer<int>;


// =====================================================================
//  DelayedWork — dispatch_after-based delayed execution (macOS)
//
//  Replaces the Windows SetTimer/KillTimer pattern.
//  Subclass and override operator() with the work to perform.
// =====================================================================

class DelayedWork
{
public:
    bool post(unsigned int delay_ms);
    void cancel();

    bool isPending() const { return _pending; }
    explicit operator bool() const { return _pending; }
    bool operator!() const { return !_pending; }

protected:
    DelayedWork() = default;
    DelayedWork(const DelayedWork&) = delete;
    DelayedWork& operator=(const DelayedWork&) = delete;

    virtual ~DelayedWork() { cancel(); }

    virtual void operator()() = 0;

private:
    bool     _pending   {false};
    uint64_t _generation {0};
};


// =====================================================================
//  IFStreamLineGetter — reads from ifstream line-by-line preserving EOL
// =====================================================================

class IFStreamLineGetter
{
public:
    IFStreamLineGetter(std::ifstream& ifs);
    ~IFStreamLineGetter() = default;

    std::string get();

private:
    static constexpr size_t cBuffSize {2048};

    IFStreamLineGetter(const IFStreamLineGetter&) = delete;
    IFStreamLineGetter(IFStreamLineGetter&&) = delete;
    IFStreamLineGetter& operator=(const IFStreamLineGetter&) = delete;

    std::ifstream&      _ifs;
    std::vector<char>   _readBuf;
    size_t              _readPos    {0};
    size_t              _countRead  {0};
};


// =====================================================================
//  SHA256 — uses Apple CommonCrypto (CC_SHA256)
// =====================================================================

class SHA256
{
public:
    SHA256() = default;
    ~SHA256() = default;

    /// Calculate SHA-256 of a byte vector. Returns 32-byte hash.
    std::vector<uint8_t> operator()(const std::vector<char>& vec);

private:
    SHA256(const SHA256&) = delete;
    SHA256(SHA256&&) = delete;
    SHA256& operator=(const SHA256&) = delete;
};


// =====================================================================
//  Utility functions
// =====================================================================

/// Convert text in-place to lowercase (UTF-8).
void toLowerCase(std::vector<char>& text, int codepage = 65001 /*CP_UTF8*/);

/// Check if a file exists and is not a directory.
inline bool fileExists(const char* filePath)
{
    if (!filePath) return false;
    struct stat st;
    if (stat(filePath, &st) != 0) return false;
    return (st.st_mode & S_IFREG) != 0;
}

/// Trim leading and trailing whitespace from a string.
inline std::string trimString(const std::string& s)
{
    size_t start = s.find_first_not_of(" \t\r\n");
    if (start == std::string::npos) return {};
    size_t end = s.find_last_not_of(" \t\r\n");
    return s.substr(start, end - start + 1);
}
