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

#include "CompareTools.h"

#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonDigest.h>
#include <dispatch/dispatch.h>


// =====================================================================
//  DelayedWork — dispatch_after implementation
// =====================================================================

bool DelayedWork::post(unsigned int delay_ms)
{
    // Bump generation to invalidate any prior pending block
    ++_generation;
    _pending = true;

    uint64_t gen = _generation;
    DelayedWork* self = this;

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)delay_ms * NSEC_PER_MSEC),
        dispatch_get_main_queue(),
        ^{
            // Only fire if this work instance is still pending and generation matches
            if (self->_pending && self->_generation == gen)
            {
                self->_pending = false;
                (*self)();
            }
        });

    return true;
}


void DelayedWork::cancel()
{
    if (_pending)
    {
        ++_generation;  // invalidate any pending dispatch block
        _pending = false;
    }
}


// =====================================================================
//  IFStreamLineGetter
// =====================================================================

IFStreamLineGetter::IFStreamLineGetter(std::ifstream& ifs) : _ifs(ifs)
{
    if (ifs.good())
    {
        _readBuf.resize(cBuffSize);
        ifs.read(_readBuf.data(), _readBuf.size());
        _countRead = static_cast<size_t>(ifs.gcount());
    }
}


std::string IFStreamLineGetter::get()
{
    std::string lineStr;

    while (true)
    {
        const size_t pos = _readPos;

        if (lineStr.empty() || (lineStr.back() != '\r' && lineStr.back() != '\n'))
        {
            while (_readPos < _countRead &&
                    *(_readBuf.data() + _readPos) != '\r' && *(_readBuf.data() + _readPos) != '\n')
                ++_readPos;
        }

        while (_readPos < _countRead &&
                (*(_readBuf.data() + _readPos) == '\r' || *(_readBuf.data() + _readPos) == '\n'))
            ++_readPos;

        lineStr.append(_readBuf.data() + pos, _readBuf.data() + _readPos);

        if (_readPos < _countRead || !_ifs.good())
            break;

        _ifs.read(_readBuf.data(), _readBuf.size());
        _countRead = static_cast<size_t>(_ifs.gcount());
        _readPos = 0;
    }

    return lineStr;
}


// =====================================================================
//  SHA256 — using Apple CommonCrypto
// =====================================================================

std::vector<uint8_t> SHA256::operator()(const std::vector<char>& vec)
{
    std::vector<uint8_t> hash(CC_SHA256_DIGEST_LENGTH);

    CC_SHA256(vec.data(), static_cast<CC_LONG>(vec.size()), hash.data());

    return hash;
}


// =====================================================================
//  toLowerCase — UTF-8 aware via NSString
// =====================================================================

void toLowerCase(std::vector<char>& text, int /*codepage*/)
{
    if (text.empty())
        return;

    @autoreleasepool {
        NSString* str = [[NSString alloc] initWithBytes:text.data()
                                                 length:text.size()
                                               encoding:NSUTF8StringEncoding];
        if (!str) return;

        NSString* lower = [str lowercaseString];
        const char* utf8 = [lower UTF8String];
        if (!utf8) return;

        size_t len = strlen(utf8);

        // If the lowercased string is exactly the same length, write in-place
        if (len == text.size())
        {
            memcpy(text.data(), utf8, len);
        }
        else
        {
            // Resize and copy (rare case: some Unicode chars change byte-length on lowercasing)
            text.assign(utf8, utf8 + len);
        }
    }
}
