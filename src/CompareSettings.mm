/*
 * This file is part of ComparePlus plugin for Notepad++ (macOS port)
 * Copyright (C)2017-2025 Pavel Nedev (pg.nedev@gmail.com)
 *
 * macOS port by Andrey Letov, 2026
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "CompareSettings.h"
#include "CompareHelpers.h"

#import <Foundation/Foundation.h>

#include <sys/stat.h>


// =====================================================================
//  JSON key constants  (match the Windows INI key names)
// =====================================================================

// --- main_settings ---
static NSString* const kFirstIsNew           = @"set_first_as_new";
static NSString* const kNewFileView          = @"new_in_sub_view";
static NSString* const kCompareToPrev        = @"default_compare_to_prev";
static NSString* const kEncodingsCheck       = @"check_encodings";
static NSString* const kSizesCheck           = @"check_sizes";
static NSString* const kManualSyncCheck      = @"check_manual_sync";
static NSString* const kPromptCloseOnMatch   = @"prompt_to_close_on_match";
static NSString* const kHideMargin           = @"hide_margin";
static NSString* const kNeverMarkIgnored     = @"never_colorize_ignored_lines";
static NSString* const kFollowingCaret       = @"following_caret";
static NSString* const kWrapAround           = @"wrap_around";
static NSString* const kGotoFirstDiff        = @"go_to_first_on_recompare";

static NSString* const kDetectMoves          = @"detect_moves";
static NSString* const kDetectSubBlockDiffs  = @"detect_sub_block_diffs";
static NSString* const kDetectSubLineMoves   = @"detect_sub_line_moves";
static NSString* const kDetectCharDiffs      = @"detect_character_diffs";
static NSString* const kIgnoreEmptyLines     = @"ignore_empty_lines";
static NSString* const kIgnoreFoldedLines    = @"ignore_folded_lines";
static NSString* const kIgnoreHiddenLines    = @"ignore_hidden_lines";
static NSString* const kIgnoreChangedSpaces  = @"ignore_changed_spaces";
static NSString* const kIgnoreAllSpaces      = @"ignore_all_spaces";
static NSString* const kIgnoreEOL            = @"ignore_eol";
static NSString* const kIgnoreCase           = @"ignore_case";
static NSString* const kIgnoreRegex          = @"ignore_regex";
static NSString* const kInvertRegex          = @"invert_regex";
static NSString* const kInclRegexNomatch     = @"incl_regex_nomatch_lines";
static NSString* const kHighlightRegexIgn    = @"highlight_regex_ignores";
static NSString* const kIgnoreRegexStr       = @"ignore_regex_strings";

static NSString* const kHideMatches          = @"hide_matches";
static NSString* const kHideNewLines         = @"hide_added_removed_lines";
static NSString* const kHideChangedLines     = @"hide_changed_lines";
static NSString* const kHideMovedLines       = @"hide_moved_lines";
static NSString* const kShowOnlySel          = @"show_only_selections";
static NSString* const kNavBar               = @"navigation_bar";

static NSString* const kBookmarksAsSync      = @"bookmarks_as_sync";
static NSString* const kRecompareOnChange    = @"recompare_on_change";
static NSString* const kStatusInfo           = @"status_info";

// --- color_settings ---
static NSString* const kAddedColor           = @"added";
static NSString* const kRemovedColor         = @"removed";
static NSString* const kMovedColor           = @"moved";
static NSString* const kChangedColor         = @"changed";
static NSString* const kAddedPartColor       = @"added_part";
static NSString* const kRemovedPartColor     = @"removed_part";
static NSString* const kMovedPartColor       = @"moved_part";
static NSString* const kPartTransp           = @"part_transparency";
static NSString* const kCaretLineTransp      = @"caret_line_transparency";

static NSString* const kAddedColorDark       = @"added_dark";
static NSString* const kRemovedColorDark     = @"removed_dark";
static NSString* const kMovedColorDark       = @"moved_dark";
static NSString* const kChangedColorDark     = @"changed_dark";
static NSString* const kAddedPartColorDark   = @"added_part_dark";
static NSString* const kRemovedPartColorDark = @"removed_part_dark";
static NSString* const kMovedPartColorDark   = @"moved_part_dark";
static NSString* const kPartTranspDark       = @"part_transparency_dark";
static NSString* const kCaretLineTranspDark  = @"caret_line_transparency_dark";

static NSString* const kChangedResembl       = @"changed_resemblance";

// --- toolbar_settings ---
static NSString* const kEnableToolbar        = @"enable_toolbar";
static NSString* const kSetAsFirstTB         = @"set_as_first_tb";
static NSString* const kCompareTB            = @"compare_tb";
static NSString* const kCompareSelTB         = @"compare_selection_tb";
static NSString* const kClearCompareTB       = @"clear_compare_tb";
static NSString* const kNavigationTB         = @"navigation_tb";
static NSString* const kDiffsFilterTB        = @"diffs_filter_tb";
static NSString* const kNavBarTB             = @"nav_bar_tb";


// =====================================================================
//  Helper: read a bool from a dictionary with a default value
// =====================================================================

static bool readBool(NSDictionary* dict, NSString* key, int defaultVal)
{
    id val = dict[key];
    if (val == nil) return (defaultVal != 0);
    return [val boolValue];
}

static int readInt(NSDictionary* dict, NSString* key, int defaultVal)
{
    id val = dict[key];
    if (val == nil) return defaultVal;
    return [val intValue];
}


// =====================================================================
//  Config file path
// =====================================================================

static std::string configFilePath()
{
    std::string path = getPluginsConfigDir();
    if (path.empty())
    {
        // Fallback
        const char* home = getenv("HOME");
        if (home)
            path = std::string(home) + "/.notepad++/plugins/Config";
    }
    path += "/ComparePlus.json";
    return path;
}


// =====================================================================
//  UserSettings::load()
// =====================================================================

void UserSettings::load()
{
    @autoreleasepool {

    dirty = false;

    // --- Set all defaults first ---
    FirstFileIsNew       = (DEFAULT_FIRST_IS_NEW != 0);
    NewFileViewId        = DEFAULT_NEW_IN_SUB_VIEW ? SUB_VIEW : MAIN_VIEW;
    CompareToPrev        = (DEFAULT_COMPARE_TO_PREV != 0);
    EncodingsCheck       = (DEFAULT_ENCODINGS_CHECK != 0);
    SizesCheck           = (DEFAULT_SIZES_CHECK != 0);
    ManualSyncCheck      = (DEFAULT_MANUAL_SYNC_CHECK != 0);
    PromptToCloseOnMatch = (DEFAULT_PROMPT_CLOSE_ON_MATCH != 0);
    HideMargin           = (DEFAULT_HIDE_MARGIN != 0);
    NeverMarkIgnored     = (DEFAULT_NEVER_MARK_IGNORED != 0);
    FollowingCaret       = (DEFAULT_FOLLOWING_CARET != 0);
    WrapAround           = (DEFAULT_WRAP_AROUND != 0);
    GotoFirstDiff        = (DEFAULT_GOTO_FIRST_DIFF != 0);

    DetectMoves          = true;
    DetectSubBlockDiffs  = true;
    DetectSubLineMoves   = true;
    DetectCharDiffs      = false;
    IgnoreEmptyLines     = false;
    IgnoreFoldedLines    = false;
    IgnoreHiddenLines    = false;
    IgnoreChangedSpaces  = false;
    IgnoreAllSpaces      = false;
    IgnoreEOL            = false;
    IgnoreCase           = false;
    IgnoreRegex          = false;
    InvertRegex          = false;
    InclRegexNomatchLines= false;
    HighlightRegexIgnores= false;

    for (int i = 0; i < cMaxRegexHistory; ++i)
        IgnoreRegexStr[i].clear();

    HideMatches          = false;
    HideNewLines         = false;
    HideChangedLines     = false;
    HideMovedLines       = false;
    ShowOnlySelections   = true;
    ShowNavBar           = true;

    BookmarksAsSync      = false;
    RecompareOnChange    = true;
    StatusInfo           = static_cast<StatusType>(DEFAULT_STATUS_INFO);

    ChangedResemblPercent = DEFAULT_CHANGED_RESEMBLANCE;

    colorsLight.added                = DEFAULT_ADDED_COLOR;
    colorsLight.removed              = DEFAULT_REMOVED_COLOR;
    colorsLight.moved                = DEFAULT_MOVED_COLOR;
    colorsLight.changed              = DEFAULT_CHANGED_COLOR;
    colorsLight.added_part           = DEFAULT_PART_COLOR;
    colorsLight.removed_part         = DEFAULT_PART_COLOR;
    colorsLight.moved_part           = DEFAULT_MOVED_PART_COLOR;
    colorsLight.part_transparency    = DEFAULT_PART_TRANSP;
    colorsLight.caret_line_transparency = DEFAULT_CARET_LINE_TRANSP;

    colorsDark.added                 = DEFAULT_ADDED_COLOR_DARK;
    colorsDark.removed               = DEFAULT_REMOVED_COLOR_DARK;
    colorsDark.moved                 = DEFAULT_MOVED_COLOR_DARK;
    colorsDark.changed               = DEFAULT_CHANGED_COLOR_DARK;
    colorsDark.added_part            = DEFAULT_PART_COLOR_DARK;
    colorsDark.removed_part          = DEFAULT_PART_COLOR_DARK;
    colorsDark.moved_part            = DEFAULT_MOVED_PART_COLOR_DARK;
    colorsDark.part_transparency     = DEFAULT_PART_TRANSP_DARK;
    colorsDark.caret_line_transparency = DEFAULT_CARET_LINE_TRANSP_DARK;

    EnableToolbar   = (DEFAULT_ENABLE_TOOLBAR_TB != 0);
    SetAsFirstTB    = (DEFAULT_SET_AS_FIRST_TB != 0);
    CompareTB       = (DEFAULT_COMPARE_TB != 0);
    CompareSelTB    = (DEFAULT_COMPARE_SEL_TB != 0);
    ClearCompareTB  = (DEFAULT_CLEAR_COMPARE_TB != 0);
    NavigationTB    = (DEFAULT_NAVIGATION_TB != 0);
    DiffsFilterTB   = (DEFAULT_DIFFS_FILTER_TB != 0);
    NavBarTB        = (DEFAULT_NAV_BAR_TB != 0);

    // --- Read JSON config file ---
    std::string path = configFilePath();
    NSString* nsPath = [NSString stringWithUTF8String:path.c_str()];
    NSData* data = [NSData dataWithContentsOfFile:nsPath];
    if (!data) return;

    NSError* err = nil;
    NSDictionary* root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (!root || err) return;

    NSDictionary* main = root[@"main_settings"];
    NSDictionary* colorsSec = root[@"color_settings"];
    NSDictionary* toolbar = root[@"toolbar_settings"];

    if (main)
    {
        FirstFileIsNew       = readBool(main, kFirstIsNew,         DEFAULT_FIRST_IS_NEW);
        NewFileViewId        = readBool(main, kNewFileView,        DEFAULT_NEW_IN_SUB_VIEW) ? SUB_VIEW : MAIN_VIEW;
        CompareToPrev        = readBool(main, kCompareToPrev,      DEFAULT_COMPARE_TO_PREV);
        EncodingsCheck       = readBool(main, kEncodingsCheck,     DEFAULT_ENCODINGS_CHECK);
        SizesCheck           = readBool(main, kSizesCheck,         DEFAULT_SIZES_CHECK);
        ManualSyncCheck      = readBool(main, kManualSyncCheck,    DEFAULT_MANUAL_SYNC_CHECK);
        PromptToCloseOnMatch = readBool(main, kPromptCloseOnMatch, DEFAULT_PROMPT_CLOSE_ON_MATCH);
        HideMargin           = readBool(main, kHideMargin,         DEFAULT_HIDE_MARGIN);
        NeverMarkIgnored     = readBool(main, kNeverMarkIgnored,   DEFAULT_NEVER_MARK_IGNORED);
        FollowingCaret       = readBool(main, kFollowingCaret,     DEFAULT_FOLLOWING_CARET);
        WrapAround           = readBool(main, kWrapAround,         DEFAULT_WRAP_AROUND);
        GotoFirstDiff        = readBool(main, kGotoFirstDiff,      DEFAULT_GOTO_FIRST_DIFF);

        DetectMoves          = readBool(main, kDetectMoves,         1);
        DetectSubBlockDiffs  = readBool(main, kDetectSubBlockDiffs, 1);
        DetectSubLineMoves   = readBool(main, kDetectSubLineMoves,  1);
        DetectCharDiffs      = readBool(main, kDetectCharDiffs,     0);
        IgnoreEmptyLines     = readBool(main, kIgnoreEmptyLines,    0);
        IgnoreFoldedLines    = readBool(main, kIgnoreFoldedLines,   0);
        IgnoreHiddenLines    = readBool(main, kIgnoreHiddenLines,   0);
        IgnoreChangedSpaces  = readBool(main, kIgnoreChangedSpaces, 0);
        IgnoreAllSpaces      = readBool(main, kIgnoreAllSpaces,     0);
        IgnoreEOL            = readBool(main, kIgnoreEOL,           0);
        IgnoreCase           = readBool(main, kIgnoreCase,          0);
        IgnoreRegex          = readBool(main, kIgnoreRegex,         0);
        InvertRegex          = readBool(main, kInvertRegex,         0);
        InclRegexNomatchLines= readBool(main, kInclRegexNomatch,    0);
        HighlightRegexIgnores= readBool(main, kHighlightRegexIgn,   0);

        // Regex history is stored as a JSON array of strings
        NSArray* regexArr = main[kIgnoreRegexStr];
        if ([regexArr isKindOfClass:[NSArray class]])
        {
            for (NSUInteger i = 0; i < regexArr.count && i < (NSUInteger)cMaxRegexHistory; ++i)
            {
                NSString* s = regexArr[i];
                if ([s isKindOfClass:[NSString class]])
                    IgnoreRegexStr[i] = s.UTF8String ?: "";
            }
        }

        HideMatches          = readBool(main, kHideMatches,        0);
        HideNewLines         = readBool(main, kHideNewLines,       0);
        HideChangedLines     = readBool(main, kHideChangedLines,   0);
        HideMovedLines       = readBool(main, kHideMovedLines,     0);
        ShowOnlySelections   = readBool(main, kShowOnlySel,        1);
        ShowNavBar           = readBool(main, kNavBar,             1);

        BookmarksAsSync      = readBool(main, kBookmarksAsSync,    0);
        RecompareOnChange    = readBool(main, kRecompareOnChange,  1);

        int si = readInt(main, kStatusInfo, DEFAULT_STATUS_INFO);
        StatusInfo = (si >= 0 && si < STATUS_TYPE_END) ? static_cast<StatusType>(si)
                                                        : static_cast<StatusType>(DEFAULT_STATUS_INFO);
    }

    if (colorsSec)
    {
        colorsLight.added                = readInt(colorsSec, kAddedColor,       DEFAULT_ADDED_COLOR);
        colorsLight.removed              = readInt(colorsSec, kRemovedColor,     DEFAULT_REMOVED_COLOR);
        colorsLight.moved                = readInt(colorsSec, kMovedColor,       DEFAULT_MOVED_COLOR);
        colorsLight.changed              = readInt(colorsSec, kChangedColor,     DEFAULT_CHANGED_COLOR);
        colorsLight.added_part           = readInt(colorsSec, kAddedPartColor,   DEFAULT_PART_COLOR);
        colorsLight.removed_part         = readInt(colorsSec, kRemovedPartColor, DEFAULT_PART_COLOR);
        colorsLight.moved_part           = readInt(colorsSec, kMovedPartColor,   DEFAULT_MOVED_PART_COLOR);
        colorsLight.part_transparency    = readInt(colorsSec, kPartTransp,       DEFAULT_PART_TRANSP);
        colorsLight.caret_line_transparency = readInt(colorsSec, kCaretLineTransp, DEFAULT_CARET_LINE_TRANSP);

        colorsDark.added                 = readInt(colorsSec, kAddedColorDark,       DEFAULT_ADDED_COLOR_DARK);
        colorsDark.removed               = readInt(colorsSec, kRemovedColorDark,     DEFAULT_REMOVED_COLOR_DARK);
        colorsDark.moved                 = readInt(colorsSec, kMovedColorDark,       DEFAULT_MOVED_COLOR_DARK);
        colorsDark.changed               = readInt(colorsSec, kChangedColorDark,     DEFAULT_CHANGED_COLOR_DARK);
        colorsDark.added_part            = readInt(colorsSec, kAddedPartColorDark,   DEFAULT_PART_COLOR_DARK);
        colorsDark.removed_part          = readInt(colorsSec, kRemovedPartColorDark, DEFAULT_PART_COLOR_DARK);
        colorsDark.moved_part            = readInt(colorsSec, kMovedPartColorDark,   DEFAULT_MOVED_PART_COLOR_DARK);
        colorsDark.part_transparency     = readInt(colorsSec, kPartTranspDark,       DEFAULT_PART_TRANSP_DARK);
        colorsDark.caret_line_transparency = readInt(colorsSec, kCaretLineTranspDark, DEFAULT_CARET_LINE_TRANSP_DARK);

        ChangedResemblPercent = readInt(colorsSec, kChangedResembl, DEFAULT_CHANGED_RESEMBLANCE);
    }

    if (toolbar)
    {
        EnableToolbar  = readBool(toolbar, kEnableToolbar,  DEFAULT_ENABLE_TOOLBAR_TB);
        SetAsFirstTB   = readBool(toolbar, kSetAsFirstTB,   DEFAULT_SET_AS_FIRST_TB);
        CompareTB      = readBool(toolbar, kCompareTB,      DEFAULT_COMPARE_TB);
        CompareSelTB   = readBool(toolbar, kCompareSelTB,   DEFAULT_COMPARE_SEL_TB);
        ClearCompareTB = readBool(toolbar, kClearCompareTB, DEFAULT_CLEAR_COMPARE_TB);
        NavigationTB   = readBool(toolbar, kNavigationTB,   DEFAULT_NAVIGATION_TB);
        DiffsFilterTB  = readBool(toolbar, kDiffsFilterTB,  DEFAULT_DIFFS_FILTER_TB);
        NavBarTB       = readBool(toolbar, kNavBarTB,       DEFAULT_NAV_BAR_TB);
    }

    } // @autoreleasepool
}


// =====================================================================
//  UserSettings::save()
// =====================================================================

void UserSettings::save()
{
    if (!dirty)
        return;

    @autoreleasepool {

    std::string path = configFilePath();

    // Ensure parent directory exists
    std::string dir = path.substr(0, path.rfind('/'));
    NSString* nsDir = [NSString stringWithUTF8String:dir.c_str()];
    NSFileManager* fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:nsDir])
    {
        NSError* err = nil;
        if (![fm createDirectoryAtPath:nsDir withIntermediateDirectories:YES attributes:nil error:&err])
        {
            NSLog(@"ComparePlus: failed to create config dir: %@", err);
            return;
        }
    }

    // Build regex history array
    NSMutableArray* regexArr = [NSMutableArray array];
    for (int i = 0; i < cMaxRegexHistory && !IgnoreRegexStr[i].empty(); ++i)
    {
        [regexArr addObject:[NSString stringWithUTF8String:IgnoreRegexStr[i].c_str()]];
    }

    // Build the JSON structure (three sections like the Windows INI)
    NSDictionary* mainDict = @{
        kFirstIsNew:          @(FirstFileIsNew),
        kNewFileView:         @(NewFileViewId == SUB_VIEW),
        kCompareToPrev:       @(CompareToPrev),
        kEncodingsCheck:      @(EncodingsCheck),
        kSizesCheck:          @(SizesCheck),
        kManualSyncCheck:     @(ManualSyncCheck),
        kPromptCloseOnMatch:  @(PromptToCloseOnMatch),
        kHideMargin:          @(HideMargin),
        kNeverMarkIgnored:    @(NeverMarkIgnored),
        kFollowingCaret:      @(FollowingCaret),
        kWrapAround:          @(WrapAround),
        kGotoFirstDiff:       @(GotoFirstDiff),

        kDetectMoves:         @(DetectMoves),
        kDetectSubBlockDiffs: @(DetectSubBlockDiffs),
        kDetectSubLineMoves:  @(DetectSubLineMoves),
        kDetectCharDiffs:     @(DetectCharDiffs),
        kIgnoreEmptyLines:    @(IgnoreEmptyLines),
        kIgnoreFoldedLines:   @(IgnoreFoldedLines),
        kIgnoreHiddenLines:   @(IgnoreHiddenLines),
        kIgnoreChangedSpaces: @(IgnoreChangedSpaces),
        kIgnoreAllSpaces:     @(IgnoreAllSpaces),
        kIgnoreEOL:           @(IgnoreEOL),
        kIgnoreCase:          @(IgnoreCase),
        kIgnoreRegex:         @(IgnoreRegex),
        kInvertRegex:         @(InvertRegex),
        kInclRegexNomatch:    @(InclRegexNomatchLines),
        kHighlightRegexIgn:   @(HighlightRegexIgnores),
        kIgnoreRegexStr:      regexArr,

        kHideMatches:         @(HideMatches),
        kHideNewLines:        @(HideNewLines),
        kHideChangedLines:    @(HideChangedLines),
        kHideMovedLines:      @(HideMovedLines),
        kShowOnlySel:         @(ShowOnlySelections),
        kNavBar:              @(ShowNavBar),

        kBookmarksAsSync:     @(BookmarksAsSync),
        kRecompareOnChange:   @(RecompareOnChange),
        kStatusInfo:          @(static_cast<int>(StatusInfo)),
    };

    NSDictionary* colorsDict = @{
        kAddedColor:          @(colorsLight.added),
        kRemovedColor:        @(colorsLight.removed),
        kMovedColor:          @(colorsLight.moved),
        kChangedColor:        @(colorsLight.changed),
        kAddedPartColor:      @(colorsLight.added_part),
        kRemovedPartColor:    @(colorsLight.removed_part),
        kMovedPartColor:      @(colorsLight.moved_part),
        kPartTransp:          @(colorsLight.part_transparency),
        kCaretLineTransp:     @(colorsLight.caret_line_transparency),

        kAddedColorDark:      @(colorsDark.added),
        kRemovedColorDark:    @(colorsDark.removed),
        kMovedColorDark:      @(colorsDark.moved),
        kChangedColorDark:    @(colorsDark.changed),
        kAddedPartColorDark:  @(colorsDark.added_part),
        kRemovedPartColorDark:@(colorsDark.removed_part),
        kMovedPartColorDark:  @(colorsDark.moved_part),
        kPartTranspDark:      @(colorsDark.part_transparency),
        kCaretLineTranspDark: @(colorsDark.caret_line_transparency),

        kChangedResembl:      @(ChangedResemblPercent),
    };

    NSDictionary* toolbarDict = @{
        kEnableToolbar:  @(EnableToolbar),
        kSetAsFirstTB:   @(SetAsFirstTB),
        kCompareTB:      @(CompareTB),
        kCompareSelTB:   @(CompareSelTB),
        kClearCompareTB: @(ClearCompareTB),
        kNavigationTB:   @(NavigationTB),
        kDiffsFilterTB:  @(DiffsFilterTB),
        kNavBarTB:       @(NavBarTB),
    };

    NSDictionary* root = @{
        @"main_settings":    mainDict,
        @"color_settings":   colorsDict,
        @"toolbar_settings": toolbarDict,
    };

    NSError* err = nil;
    NSData* jsonData = [NSJSONSerialization dataWithJSONObject:root
                                                       options:NSJSONWritingSortedKeys | NSJSONWritingPrettyPrinted
                                                         error:&err];
    if (jsonData && !err)
    {
        NSString* nsPath = [NSString stringWithUTF8String:path.c_str()];
        [jsonData writeToFile:nsPath atomically:YES];
    }
    else
    {
        NSLog(@"ComparePlus: failed to serialize settings: %@", err);
    }

    dirty = false;

    } // @autoreleasepool
}


// =====================================================================
//  UserSettings::moveRegexToHistory()
// =====================================================================

void UserSettings::moveRegexToHistory(std::string&& newRegex)
{
    int i = 0;
    for (; i < cMaxRegexHistory && !IgnoreRegexStr[i].empty() && IgnoreRegexStr[i] != newRegex; ++i)
        ;

    if (i < cMaxRegexHistory)
        --i;
    else
        i = cMaxRegexHistory - 2;

    for (; i >= 0; --i)
        IgnoreRegexStr[i + 1] = std::move(IgnoreRegexStr[i]);

    IgnoreRegexStr[0] = std::move(newRegex);
}
