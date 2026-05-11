/*
 * This file is part of ComparePlus plugin for Notepad++ (macOS port)
 * Copyright (C)2017-2025 Pavel Nedev (pg.nedev@gmail.com)
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

#include <string>


// =====================================================================
//  Default values (same as Windows UserSettings.h)
// =====================================================================

#define DEFAULT_FIRST_IS_NEW              1
#define DEFAULT_NEW_IN_SUB_VIEW           1
#define DEFAULT_COMPARE_TO_PREV           1

#define DEFAULT_ENCODINGS_CHECK           1
#define DEFAULT_SIZES_CHECK               1
#define DEFAULT_MANUAL_SYNC_CHECK         1
#define DEFAULT_PROMPT_CLOSE_ON_MATCH     0
#define DEFAULT_HIDE_MARGIN               0
#define DEFAULT_NEVER_MARK_IGNORED        0
#define DEFAULT_FOLLOWING_CARET           1
#define DEFAULT_WRAP_AROUND               0
#define DEFAULT_GOTO_FIRST_DIFF           1

#define DEFAULT_STATUS_INFO               0

// Colors are BGR (Scintilla convention)
#define DEFAULT_ADDED_COLOR               0xC6FFC6
#define DEFAULT_REMOVED_COLOR             0xC6C6FF
#define DEFAULT_MOVED_COLOR               0xFFE6CC
#define DEFAULT_CHANGED_COLOR             0x98E7E7
#define DEFAULT_PART_COLOR                0x0683FF
#define DEFAULT_MOVED_PART_COLOR          0xF58742
#define DEFAULT_PART_TRANSP               0
#define DEFAULT_CARET_LINE_TRANSP         60

#define DEFAULT_ADDED_COLOR_DARK          0x055A05
#define DEFAULT_REMOVED_COLOR_DARK        0x16164F
#define DEFAULT_MOVED_COLOR_DARK          0x4F361C
#define DEFAULT_CHANGED_COLOR_DARK        0x145050
#define DEFAULT_PART_COLOR_DARK           0x0683FF
#define DEFAULT_MOVED_PART_COLOR_DARK     0xF58742
#define DEFAULT_PART_TRANSP_DARK          0
#define DEFAULT_CARET_LINE_TRANSP_DARK    80

#define DEFAULT_CHANGED_RESEMBLANCE       20

#define DEFAULT_ENABLE_TOOLBAR_TB         1
#define DEFAULT_SET_AS_FIRST_TB           1
#define DEFAULT_COMPARE_TB                1
#define DEFAULT_COMPARE_SEL_TB            1
#define DEFAULT_CLEAR_COMPARE_TB          1
#define DEFAULT_NAVIGATION_TB             1
#define DEFAULT_DIFFS_FILTER_TB           1
#define DEFAULT_NAV_BAR_TB                1


// =====================================================================
//  StatusType enum
// =====================================================================

enum StatusType
{
    DIFFS_SUMMARY = 0,
    COMPARE_OPTIONS,
    STATUS_DISABLED,
    STATUS_TYPE_END
};


// =====================================================================
//  ColorSettings — per-theme color set
// =====================================================================

struct ColorSettings
{
    int added;
    int removed;
    int changed;
    int moved;
    int blank;
    int _default;
    int added_part;
    int removed_part;
    int moved_part;
    int part_transparency;
    int caret_line_transparency;
};


// =====================================================================
//  UserSettings — all persistent plugin settings
//
//  On macOS the config is stored as JSON in:
//      ~/.nextpad++/plugins/Config/ComparePlus.json
//  rather than a Windows INI file.
// =====================================================================

struct UserSettings
{
public:
    UserSettings() : _colors(&colorsLight) {}

    /// Load settings from JSON config file.
    void load();

    /// Save settings to JSON config file (only if dirty).
    void save();

    void markAsDirty()   { dirty = true; }

    void useLightColors() { _colors = &colorsLight; }
    void useDarkColors()  { _colors = &colorsDark;  }

    ColorSettings& colors() { return *_colors; }

    void moveRegexToHistory(std::string&& newRegex);

    static constexpr int cMaxRegexLen     = 2047;
    static constexpr int cMaxRegexHistory = 5;

    // --- General settings ---
    bool            FirstFileIsNew;
    int             NewFileViewId;
    bool            CompareToPrev;

    bool            EncodingsCheck;
    bool            SizesCheck;
    bool            ManualSyncCheck;
    bool            PromptToCloseOnMatch;
    bool            HideMargin;
    bool            NeverMarkIgnored;
    bool            FollowingCaret;
    bool            WrapAround;
    bool            GotoFirstDiff;

    // --- Diff engine options ---
    bool            DetectMoves;
    bool            DetectSubBlockDiffs;
    bool            DetectSubLineMoves;
    bool            DetectCharDiffs;
    bool            IgnoreEmptyLines;
    bool            IgnoreFoldedLines;
    bool            IgnoreHiddenLines;
    bool            IgnoreChangedSpaces;
    bool            IgnoreAllSpaces;
    bool            IgnoreEOL;
    bool            IgnoreCase;
    bool            IgnoreRegex;
    bool            InvertRegex;
    bool            InclRegexNomatchLines;
    bool            HighlightRegexIgnores;
    std::string     IgnoreRegexStr[cMaxRegexHistory];

    // --- Display filters ---
    bool            HideMatches;
    bool            HideNewLines;
    bool            HideChangedLines;
    bool            HideMovedLines;
    bool            ShowOnlySelections;
    bool            ShowNavBar;

    // --- Misc ---
    bool            BookmarksAsSync;
    bool            RecompareOnChange;
    StatusType      StatusInfo;

    int             ChangedResemblPercent;

    // --- Toolbar (not applicable on macOS but kept for settings parity) ---
    bool            EnableToolbar;
    bool            SetAsFirstTB;
    bool            CompareTB;
    bool            CompareSelTB;
    bool            ClearCompareTB;
    bool            NavigationTB;
    bool            DiffsFilterTB;
    bool            NavBarTB;

private:
    bool dirty {false};

    ColorSettings   colorsLight;
    ColorSettings   colorsDark;
    ColorSettings*  _colors;
};
