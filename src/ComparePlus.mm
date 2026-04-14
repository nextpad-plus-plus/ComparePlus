/*
 * This file is part of ComparePlus plugin for Notepad++ (macOS port)
 * Copyright (C)2011 Jean-Sebastien Leroy (jean.sebastien.leroy@gmail.com)
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


#include "NppPluginInterfaceMac.h"
#include "Scintilla.h"

// Fallback definitions for NPPM_SETPLUGINSUBSCRIPTIONS (macOS-specific
// extension added in host v1.0.2). If the plugin is built against an
// older NppPluginInterfaceMac.h that predates this message, we still
// compile — the call at runtime falls through to the host's default
// case and returns 0 (harmless no-op on old hosts).
#ifndef NPPM_SETPLUGINSUBSCRIPTIONS
#  define NPPM_SETPLUGINSUBSCRIPTIONS      (NPPMSG + 500)
#  define NPPPLUGIN_WANTS_UPDATEUI         (1U << 0)
#  define NPPPLUGIN_WANTS_PAINTED          (1U << 1)
#endif

#include "CompareHelpers.h"
#include "CompareSettings.h"
#include "Engine/Engine.h"
#include "Engine/diff.h"
#include "Engine/diff_types.h"

#import <Cocoa/Cocoa.h>
#include <CommonCrypto/CommonDigest.h>

#include <cstring>
#include <string>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <functional>
#include <sstream>
#include <cstdint>
#include <cassert>


// =====================================================================
//  Plugin identity
// =====================================================================

static const char* PLUGIN_NAME = "ComparePlus";
static const char* PLUGIN_VERSION = "1.0.0";


// =====================================================================
//  Menu item count (including separators)
// =====================================================================

static const int NB_MENU_COMMANDS = 37;

static FuncItem funcItem[NB_MENU_COMMANDS];


// =====================================================================
//  Globals exported for CompareHelpers / Engine
// =====================================================================

NppData nppData;

int nppBookmarkMarker = -1;
int indicatorHighlight = -1;
int marginNum = -1;
int gMarginWidth = 20;

// Globals required by Engine.cpp
CompareColors compareColors;
progress_ptr globalProgress;


// =====================================================================
//  Internal plugin state
// =====================================================================

static UserSettings Settings;

static bool pluginReady = false;
static bool compareMode = false;
static bool scrollSyncEnabled = true;
static bool autoRecompareEnabled = false;
static bool bookmarksAsSyncPoints = false;
static bool navBarVisible = false;


// Allocated marker IDs (base offset from NPPM_ALLOCATEMARKER)
static int markerBaseId = -1;

// Active compare data
static CompareSummary activeSummary;
static intptr_t compareBuffIds[2] = { -1, -1 }; // [MAIN_VIEW], [SUB_VIEW]

// Pending auto-recompare flag
static bool recompareNeeded = false;

// Reentrancy guard for scroll sync
static bool syncingScroll = false;


// =====================================================================
//  Keyboard shortcut definitions (static storage)
// =====================================================================

// Ctrl+Alt+C
static ShortcutKey skCompare         = { true, true, false, false, 'C' };
// Ctrl+Alt+N
static ShortcutKey skCompareSel      = { true, true, false, false, 'N' };
// Ctrl+Alt+Shift+C
static ShortcutKey skFindUnique      = { true, true, true, false, 'C' };
// Ctrl+Alt+Shift+N
static ShortcutKey skFindUniqueSel   = { true, true, true, false, 'N' };
// Ctrl+Alt+D
static ShortcutKey skDiffSinceSave   = { true, true, false, false, 'D' };
// Ctrl+Alt+M
static ShortcutKey skCompareClip     = { true, true, false, false, 'M' };
// Ctrl+Alt+V
static ShortcutKey skSVNDiff         = { true, true, false, false, 'V' };
// Ctrl+Alt+G
static ShortcutKey skGitDiff         = { true, true, false, false, 'G' };
// Ctrl+Alt+X
static ShortcutKey skClearActive     = { true, true, false, false, 'X' };
// Alt+PageUp
static ShortcutKey skPrevDiff        = { false, true, false, false, 0x21 }; // NSPageUpFunctionKey mapped to VK_PRIOR
// Alt+PageDown
static ShortcutKey skNextDiff        = { false, true, false, false, 0x22 }; // NSPageDownFunctionKey mapped to VK_NEXT
// Ctrl+Alt+PageUp
static ShortcutKey skFirstDiff       = { true, true, false, false, 0x21 };
// Ctrl+Alt+PageDown
static ShortcutKey skLastDiff        = { true, true, false, false, 0x22 };
// Ctrl+Alt+Shift+PageUp
static ShortcutKey skPrevChangedLine = { true, true, true, false, 0x21 };
// Ctrl+Alt+Shift+PageDown
static ShortcutKey skNextChangedLine = { true, true, true, false, 0x22 };


// =====================================================================
//  Forward declarations  --  menu command callbacks
// =====================================================================

static void cmdCompare();
static void cmdCompareSelections();
static void cmdFindUniqueLines();
static void cmdFindUniqueLinesInSel();
static void cmdDiffSinceLastSave();
static void cmdCompareToClipboard();
static void cmdSVNDiff();
static void cmdGitDiff();
static void cmdClearActiveCompare();
static void cmdClearAllCompares();
static void cmdPrevDiffBlock();
static void cmdNextDiffBlock();
static void cmdFirstDiffBlock();
static void cmdLastDiffBlock();
static void cmdPrevDiffInChangedLine();
static void cmdNextDiffInChangedLine();
static void cmdActiveCompareSummary();
static void cmdCopyVisibleLines();
static void cmdDeleteVisibleLines();
static void cmdBookmarkVisibleLines();
static void cmdCompareOptions();
static void cmdBookmarksAsSyncPoints();
static void cmdDiffsVisualFilters();
static void cmdNavigationBar();
static void cmdAutoRecompare();
static void cmdSettings();
static void cmdHelpAbout();


// =====================================================================
//  Forward declarations  --  internal helpers
// =====================================================================

static void doCompare(bool selectionOnly, bool findUniqueMode, bool skipSetup = false);
static void clearCompare(int view);
static void clearAllCompares();
static void navigateToDiff(bool forward, bool firstLast);
static void navigateInChangedLine(bool forward);
static void setupMarkers();
static void applyMarkerColors();
static void syncScrollPositions(int changedView);
static void showSettingsDialog();
static void showCompareOptionsDialog();
static void showDiffsVisualFiltersDialog();
static void showAboutDialog();
static void updateMenuChecks();
static intptr_t getBuffIdForView(int view);
static std::string getFilePath(intptr_t buffId);
static void showMessage(NSString* title, NSString* info);


// =====================================================================
//  Marker setup
// =====================================================================

static void setupMarkers()
{
    // Try to allocate markers from Notepad++
    int allocated = -1;
    intptr_t result = nppData._sendMessage(nppData._nppHandle, NPPM_ALLOCATEMARKER, 16, (intptr_t)&allocated);

    if (result && allocated >= 0)
        markerBaseId = allocated;
    else
        markerBaseId = 0; // fallback: use markers 0-15 (safe — fold markers are 25-31)

    // Allocate indicator for within-line changes
    allocateIndicator();

    // Allocate margin for symbols
    allocateMarginNum();

    // Read Npp bookmark marker ID
    readNppBookmarkID();

    // NOTE: applyMarkerColors() is deferred to compare-time to avoid
    // corrupting fold markers (25-31) at startup with SCI_MARKERDEFINE calls.
}


static void applyMarkerColors()
{
    // Select light or dark colors based on mode
    if (isDarkModeNPP())
        Settings.useDarkColors();
    else
        Settings.useLightColors();

    ColorSettings& colors = Settings.colors();

    for (int view = 0; view < 2; ++view)
    {
        // Line background markers (SC_MARK_BACKGROUND)
        int lineMarkers[] = {
            MARKER_CHANGED_LINE,
            MARKER_ADDED_LINE,
            MARKER_REMOVED_LINE,
            MARKER_MOVED_LINE,
            MARKER_BLANK
        };
        int lineColors[] = {
            colors.changed,
            colors.added,
            colors.removed,
            colors.moved,
            colors._default
        };

        for (int i = 0; i < 5; ++i)
        {
            int mid = markerBaseId + lineMarkers[i];
            CallScintilla(view, SCI_MARKERDEFINE, mid, SC_MARK_BACKGROUND);
            CallScintilla(view, SCI_MARKERSETBACK, mid, lineColors[i]);
            CallScintilla(view, SCI_MARKERSETFORE, mid, lineColors[i]);
        }

        // Symbol markers for the margin
        struct SymbolDef {
            int marker;
            int shape;
            int color;
        };

        SymbolDef symbols[] = {
            { MARKER_CHANGED_SYMBOL,          SC_MARK_FULLRECT,      colors.changed },
            { MARKER_CHANGED_LOCAL_SYMBOL,    SC_MARK_FULLRECT,      colors.changed },
            { MARKER_ADDED_SYMBOL,            SC_MARK_FULLRECT,      colors.added },
            { MARKER_ADDED_LOCAL_SYMBOL,      SC_MARK_FULLRECT,      colors.added },
            { MARKER_REMOVED_SYMBOL,          SC_MARK_FULLRECT,      colors.removed },
            { MARKER_REMOVED_LOCAL_SYMBOL,    SC_MARK_FULLRECT,      colors.removed },
            { MARKER_MOVED_LINE_SYMBOL,       SC_MARK_FULLRECT,      colors.moved },
            { MARKER_MOVED_BLOCK_BEGIN_SYMBOL,SC_MARK_FULLRECT,      colors.moved },
            { MARKER_MOVED_BLOCK_MID_SYMBOL,  SC_MARK_VLINE,         colors.moved },
            { MARKER_MOVED_BLOCK_END_SYMBOL,  SC_MARK_LCORNERCURVE,  colors.moved },
            { MARKER_ARROW_SYMBOL,            SC_MARK_ARROW,         0x000000 },
        };

        for (const auto& s : symbols)
        {
            int mid = markerBaseId + s.marker;
            CallScintilla(view, SCI_MARKERDEFINE, mid, s.shape);
            CallScintilla(view, SCI_MARKERSETBACK, mid, s.color);
            CallScintilla(view, SCI_MARKERSETFORE, mid, s.color);
        }

        // Configure indicator for within-line highlights
        if (indicatorHighlight >= 0)
        {
            CallScintilla(view, SCI_INDICSETSTYLE, indicatorHighlight, INDIC_ROUNDBOX);
            CallScintilla(view, SCI_INDICSETFORE, indicatorHighlight, colors.added_part);
            CallScintilla(view, SCI_INDICSETALPHA, indicatorHighlight, 100);
            CallScintilla(view, SCI_INDICSETOUTLINEALPHA, indicatorHighlight, 255);
            CallScintilla(view, SCI_INDICSETUNDER, indicatorHighlight, 1);
        }

        // Set up compare margin (symbol column)
        if (marginNum >= 0)
        {
            CallScintilla(view, SCI_SETMARGINTYPEN, marginNum, SC_MARGIN_SYMBOL);
            CallScintilla(view, SCI_SETMARGINWIDTHN, marginNum, Settings.HideMargin ? 0 : gMarginWidth);
            CallScintilla(view, SCI_SETMARGINSENSITIVEN, marginNum, 0);

            // Build a mask of all our marker IDs
            int mask = 0;
            for (int m = 0; m < 16; ++m)
                mask |= (1 << (markerBaseId + m));
            CallScintilla(view, SCI_SETMARGINMASKN, marginNum, mask);
        }
    }
}


// =====================================================================
//  Buffer ID / path helpers
// =====================================================================

static intptr_t getBuffIdForView(int view)
{
    // The macOS plugin host doesn't support NPPM_GETBUFFERIDFROMPOS/NPPM_GETCURRENTDOCINDEX.
    // Instead, we can get the current buffer ID directly — but only for the active view.
    // For the OTHER view, we need to temporarily switch to it.
    int currentView = getCurrentViewId();
    if (view == currentView) {
        return getCurrentBuffId();
    }
    // For the other view, use the scintilla handle to get doc pointer as a buffer ID proxy.
    // The macOS host uses EditorView* pointers as buffer IDs.
    // SCI_GETDOCPOINTER gives us a unique doc identifier for each view.
    return CallScintilla(view, SCI_GETDOCPOINTER, 0, 0);
}


static std::string getFilePath(intptr_t buffId)
{
    char buf[1024] = {};
    nppData._sendMessage(nppData._nppHandle, NPPM_GETFULLPATHFROMBUFFERID, buffId, (intptr_t)buf);
    return std::string(buf);
}


// =====================================================================
//  Message/Alert helper
// =====================================================================

static void showMessage(NSString* title, NSString* info)
{
    @autoreleasepool {
        NSAlert* a = [[NSAlert alloc] init];
        a.messageText = title;
        a.informativeText = info;
        [a runModal];
    }
}


// =====================================================================
//  Alignment blanks — insert annotation-based blank lines to align diffs
// =====================================================================

static void alignDiffs()
{
    if (activeSummary.alignmentInfo.empty())
        return;

    // Clear any previous alignment annotations
    CallScintilla(MAIN_VIEW, SCI_ANNOTATIONCLEARALL, 0, 0);
    CallScintilla(SUB_VIEW, SCI_ANNOTATIONCLEARALL, 0, 0);

    // Enable annotation display
    CallScintilla(MAIN_VIEW, SCI_ANNOTATIONSETVISIBLE, ANNOTATION_STANDARD, 0);
    CallScintilla(SUB_VIEW, SCI_ANNOTATIONSETVISIBLE, ANNOTATION_STANDARD, 0);

    const auto& align = activeSummary.alignmentInfo;

    for (size_t i = 0; i + 1 < align.size(); ++i)
    {
        const intptr_t mainEnd = align[i + 1].main.line;
        const intptr_t subEnd  = align[i + 1].sub.line;

        const intptr_t mainSpan = mainEnd - align[i].main.line;
        const intptr_t subSpan  = subEnd  - align[i].sub.line;

        if (mainSpan > subSpan)
        {
            // Sub view needs blank lines to match the main view's span
            intptr_t blanks = mainSpan - subSpan;
            // addBlankSection uses getPreviousUnhiddenLine(view, line), so passing
            // subEnd places the annotation after the last line of this sub section.
            if (subEnd > 0 && subEnd <= getLinesCount(SUB_VIEW))
                addBlankSection(SUB_VIEW, subEnd, blanks);
        }
        else if (subSpan > mainSpan)
        {
            // Main view needs blank lines to match the sub view's span
            intptr_t blanks = subSpan - mainSpan;
            if (mainEnd > 0 && mainEnd <= getLinesCount(MAIN_VIEW))
                addBlankSection(MAIN_VIEW, mainEnd, blanks);
        }
    }
}


// =====================================================================
//  IDM constants for NPPM_MENUCOMMAND
// =====================================================================

// =====================================================================
//  Host action helper — get the window controller and call a selector.
// =====================================================================

static id getHostController()
{
    NSWindow *w = [NSApp mainWindow];
    if (!w) w = [NSApp keyWindow];
    if (!w) w = [[NSApp orderedWindows] firstObject];
    return w ? [w windowController] : nil;
}

static void hostAction(SEL sel)
{
    id wc = getHostController();
    if (wc && [wc respondsToSelector:sel]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [wc performSelector:sel withObject:nil];
        #pragma clang diagnostic pop
    }
}


// Pre-captured selection lines for selection compare (set before doCompare)
static std::pair<intptr_t, intptr_t> savedSelectionMain = {-1, -1};
static std::pair<intptr_t, intptr_t> savedSelectionSub  = {-1, -1};


// =====================================================================
//  Core compare implementation
// =====================================================================

static void doCompare(bool selectionOnly, bool findUniqueMode, bool skipSetup)
{
    @autoreleasepool {

    if (!skipSetup)
    {
        // Check that at least 2 files are open.
        id wc = getHostController();
        if (wc)
        {
            int count = 0;
            @try {
                id primaryTM = [wc valueForKey:@"_tabManager"];
                id subTMV    = [wc valueForKey:@"_subTabManagerV"];
                if (primaryTM)
                    count += [[primaryTM valueForKey:@"allEditors"] count];
                if (subTMV)
                    count += [[subTMV valueForKey:@"allEditors"] count];
            } @catch (...) {}

            if (count < 2)
            {
                showMessage(@"ComparePlus", @"You should have at least 2 open files to compare.");
                return;
            }
        }

        // Step 1: Move active tab to Other Vertical View
        hostAction(@selector(moveToOtherVerticalView:));
    }

    // Step 2: Run the compare
    int currentViewId = getCurrentViewId();

    int view1 = MAIN_VIEW;
    int view2 = SUB_VIEW;

    int filesInMain = getNumberOfFiles(MAIN_VIEW);
    int filesInSub  = getNumberOfFiles(SUB_VIEW);

    if (filesInMain == 0 || filesInSub == 0)
    {
        showMessage(@"ComparePlus", @"Two files are needed to compare.");
        return;
    }

    // Verify both views have content
    if (isFileEmpty(view1) && isFileEmpty(view2))
    {
        showMessage(@"ComparePlus", @"Both files are empty, nothing to compare.");
        return;
    }

    // Clear any previous compare
    clearAllCompares();

    // Store buffer IDs for the compare pair
    compareBuffIds[MAIN_VIEW] = getBuffIdForView(MAIN_VIEW);
    compareBuffIds[SUB_VIEW]  = getBuffIdForView(SUB_VIEW);

    // Encoding check
    if (Settings.EncodingsCheck)
    {
        int enc1 = getEncoding(compareBuffIds[view1]);
        int enc2 = getEncoding(compareBuffIds[view2]);
        if (enc1 != enc2)
        {
            NSAlert* alert = [[NSAlert alloc] init];
            alert.messageText = @"Encoding Mismatch";
            alert.informativeText = @"The two files have different encodings. "
                @"The comparison result may not be meaningful. Continue?";
            [alert addButtonWithTitle:@"Continue"];
            [alert addButtonWithTitle:@"Cancel"];
            if ([alert runModal] != NSAlertFirstButtonReturn)
                return;
        }
    }

    // Build CompareOptions from Settings
    CompareOptions options;
    options.newFileViewId        = Settings.NewFileViewId;
    options.findUniqueMode       = findUniqueMode;
    options.neverMarkIgnored     = Settings.NeverMarkIgnored;
    options.detectMoves          = Settings.DetectMoves;
    options.detectSubBlockDiffs  = Settings.DetectSubBlockDiffs;
    options.detectSubLineMoves   = Settings.DetectSubLineMoves;
    options.detectCharDiffs      = Settings.DetectCharDiffs;
    options.ignoreEmptyLines     = Settings.IgnoreEmptyLines;
    options.ignoreFoldedLines    = Settings.IgnoreFoldedLines;
    options.ignoreHiddenLines    = Settings.IgnoreHiddenLines;
    options.ignoreChangedSpaces  = Settings.IgnoreChangedSpaces;
    options.ignoreAllSpaces      = Settings.IgnoreAllSpaces;
    options.ignoreEOL            = Settings.IgnoreEOL;
    options.ignoreCase           = Settings.IgnoreCase;
    options.bookmarksAsSync      = bookmarksAsSyncPoints;
    options.recompareOnChange    = autoRecompareEnabled;
    options.changedResemblPercent = Settings.ChangedResemblPercent;
    options.selectionCompare     = selectionOnly;

    if (selectionOnly)
    {
        // Use pre-captured selections if available (set by cmdCompareSelections
        // before the tab move), otherwise read from views directly.
        if (savedSelectionMain.first >= 0 && savedSelectionSub.first >= 0)
        {
            options.selections[MAIN_VIEW] = savedSelectionMain;
            options.selections[SUB_VIEW]  = savedSelectionSub;
        }
        else
        {
            options.selections[view1] = getSelectionLines(view1);
            options.selections[view2] = getSelectionLines(view2);
        }
    }

    // Set up ignore regex if configured
    if (Settings.IgnoreRegex && !Settings.IgnoreRegexStr[0].empty())
    {
        options.setIgnoreRegex(Settings.IgnoreRegexStr[0],
            Settings.InvertRegex, Settings.InclRegexNomatchLines,
            Settings.HighlightRegexIgnores, Settings.IgnoreCase);
    }

    // Collect bookmark sync points if enabled
    if (bookmarksAsSyncPoints)
    {
        auto bm1 = getAllBookmarkedLines(view1);
        auto bm2 = getAllBookmarkedLines(view2);

        size_t count = std::min(bm1.size(), bm2.size());
        for (size_t i = 0; i < count; ++i)
            options.syncPoints.push_back(std::make_pair(bm1[i], bm2[i]));

        if (Settings.ManualSyncCheck && bm1.size() != bm2.size())
        {
            NSAlert* alert = [[NSAlert alloc] init];
            alert.messageText = @"Sync Point Mismatch";
            alert.informativeText = [NSString stringWithFormat:
                @"Different number of bookmarks in the two views (%zu vs %zu). "
                @"Only the first %zu pairs will be used as sync points.",
                bm1.size(), bm2.size(), count];
            [alert addButtonWithTitle:@"Continue"];
            [alert addButtonWithTitle:@"Cancel"];
            if ([alert runModal] != NSAlertFirstButtonReturn)
                return;
        }
    }

    // Set up compare view styling
    setCompareView(view1, !Settings.HideMargin, Settings.colors().blank,
                   Settings.colors().caret_line_transparency);
    setCompareView(view2, !Settings.HideMargin, Settings.colors().blank,
                   Settings.colors().caret_line_transparency);

    // Apply marker definitions now (deferred from startup to avoid fold marker corruption)
    applyMarkerColors();

    // Apply current marker styles
    setStyles(Settings);

    // Run the comparison engine
    activeSummary.clear();
    CompareResult result = compareViews(options, "Comparing...", activeSummary);

    if (result == CompareResult::COMPARE_ERROR)
    {
        clearAllCompares();
        showMessage(@"ComparePlus", @"An error occurred during comparison.");
        return;
    }

    if (result == CompareResult::COMPARE_CANCELLED)
    {
        clearAllCompares();
        return;
    }

    if (result == CompareResult::COMPARE_MATCH)
    {
        if (Settings.PromptToCloseOnMatch)
        {
            NSAlert* alert = [[NSAlert alloc] init];
            alert.messageText = @"Files Match";
            alert.informativeText = @"The two files are identical. Clear comparison?";
            [alert addButtonWithTitle:@"Clear"];
            [alert addButtonWithTitle:@"Keep"];
            if ([alert runModal] == NSAlertFirstButtonReturn)
            {
                clearAllCompares();
                return;
            }
        }
        else
        {
            showMessage(@"ComparePlus", @"The two files are identical.");
            clearAllCompares();
            return;
        }
    }

    // Insert alignment blank annotations so diff blocks line up visually
    alignDiffs();

    // Hide lines outside selection range for selection compare
    if (selectionOnly)
    {
        hideLinesOutsideRange(view1, options.selections[view1].first, options.selections[view1].second);
        hideLinesOutsideRange(view2, options.selections[view2].first, options.selections[view2].second);
    }

    // Apply visual filters
    if (Settings.HideMatches)
        hideLines(view1, 0, true);  // hide unmarked = matches

    if (Settings.HideNewLines)
    {
        hideLines(view1, MARKER_MASK_NEW_LINE, false);
        hideLines(view2, MARKER_MASK_NEW_LINE, false);
    }

    if (Settings.HideChangedLines)
    {
        hideLines(view1, MARKER_MASK_CHANGED_LINE, false);
        hideLines(view2, MARKER_MASK_CHANGED_LINE, false);
    }

    if (Settings.HideMovedLines)
    {
        hideLines(view1, MARKER_MASK_MOVED_LINE, false);
        hideLines(view2, MARKER_MASK_MOVED_LINE, false);
    }

    compareMode = true;

    // Show status bar info
    if (Settings.StatusInfo == DIFFS_SUMMARY)
    {
        char statusBuf[256];
        snprintf(statusBuf, sizeof(statusBuf),
            "Diffs: %lld  Added: %lld  Removed: %lld  Changed: %lld  Moved: %lld",
            (long long)activeSummary.diffLines,
            (long long)activeSummary.added,
            (long long)activeSummary.removed,
            (long long)activeSummary.changed,
            (long long)activeSummary.moved);
        nppData._sendMessage(nppData._nppHandle, NPPM_SETSTATUSBAR, STATUSBAR_DOC_TYPE, (intptr_t)statusBuf);
    }

    // Navigate to first diff if enabled
    if (Settings.GotoFirstDiff)
        cmdFirstDiffBlock();

    // Step 3: Enable scroll sync AFTER compare and alignment are complete
    hostAction(@selector(enableSyncScrolling:));

    // Sync initial scroll positions
    intptr_t firstLine = getFirstVisibleLine(currentViewId);
    CallScintilla(getOtherViewId(currentViewId), SCI_SETFIRSTVISIBLELINE, firstLine, 0);

    } // @autoreleasepool
}


// =====================================================================
//  Clear compare
// =====================================================================

static void clearCompare(int view)
{
    clearWindow(view, true);
    setNormalView(view);
    unhideAllLines(view);
}


static void clearAllCompares()
{
    if (!compareMode)
        return;

    clearCompare(MAIN_VIEW);
    clearCompare(SUB_VIEW);

    compareMode = false;
    compareBuffIds[0] = -1;
    compareBuffIds[1] = -1;
    activeSummary.clear();
    recompareNeeded = false;

    nppData._sendMessage(nppData._nppHandle, NPPM_SETSTATUSBAR, STATUSBAR_DOC_TYPE, (intptr_t)"");
}


// =====================================================================
//  Navigation
// =====================================================================

// Jump to a diff line in both views: center, move caret, highlight in purple
static void jumpToDiffLine(int view, intptr_t line)
{
    int otherView = getOtherViewId(view);
    intptr_t otherLine = otherViewMatchingLine(view, line);
    if (otherLine < 0)
        otherLine = line; // fallback: same line number

    // Set caret line background to #dec9f8 (purple highlight) in both views,
    // visible even in the unfocused view.
    constexpr int purple = 0x60f8c9de; // #dec9f8 with ~37% alpha
    for (int v = 0; v < 2; ++v)
    {
        CallScintilla(v, SCI_SETELEMENTCOLOUR, SC_ELEMENT_CARET_LINE_BACK, purple);
        CallScintilla(v, SCI_SETCARETLINELAYER, SC_LAYER_UNDER_TEXT, 0);
        CallScintilla(v, SCI_SETCARETLINEVISIBLEALWAYS, 1, 0);
    }

    // Center and move caret in both views
    centerAt(view, line);
    CallScintilla(view, SCI_GOTOLINE, line, 0);

    centerAt(otherView, otherLine);
    CallScintilla(otherView, SCI_GOTOLINE, otherLine, 0);
}


static void navigateToDiff(bool forward, bool firstLast)
{
    if (!compareMode)
    {
        showMessage(@"ComparePlus", @"No active comparison.");
        return;
    }

    int view = getCurrentViewId();
    intptr_t currentLine = getCurrentLine(view);
    intptr_t totalLines = getLinesCount(view);

    int searchMask = MARKER_MASK_LINE | MARKER_MASK_BLANK;

    if (firstLast)
    {
        if (forward)
        {
            // Last diff: search backward from end
            for (intptr_t line = totalLines - 1; line >= 0; --line)
            {
                if (isLineMarked(view, line, searchMask))
                {
                    intptr_t blockStart = line;
                    while (blockStart > 0 && isLineMarked(view, blockStart - 1, searchMask))
                        --blockStart;
                    jumpToDiffLine(view, blockStart);
                    return;
                }
            }
        }
        else
        {
            // First diff: search forward from start
            for (intptr_t line = 0; line < totalLines; ++line)
            {
                if (isLineMarked(view, line, searchMask))
                {
                    jumpToDiffLine(view, line);
                    return;
                }
            }
        }
    }
    else
    {
        if (forward)
        {
            // Skip current block
            intptr_t startLine = currentLine;
            while (startLine < totalLines && isLineMarked(view, startLine, searchMask))
                ++startLine;

            intptr_t nextDiff = CallScintilla(view, SCI_MARKERNEXT, startLine, searchMask);

            if (nextDiff < 0 && Settings.WrapAround)
                nextDiff = CallScintilla(view, SCI_MARKERNEXT, 0, searchMask);

            if (nextDiff >= 0)
                jumpToDiffLine(view, nextDiff);
        }
        else
        {
            intptr_t startLine = currentLine;

            while (startLine > 0 && isLineMarked(view, startLine, searchMask))
                --startLine;

            intptr_t prevDiff = CallScintilla(view, SCI_MARKERPREVIOUS, startLine, searchMask);

            if (prevDiff < 0 && Settings.WrapAround)
                prevDiff = CallScintilla(view, SCI_MARKERPREVIOUS, totalLines - 1, searchMask);

            if (prevDiff >= 0)
            {
                intptr_t blockStart = prevDiff;
                while (blockStart > 0 && isLineMarked(view, blockStart - 1, searchMask))
                    --blockStart;
                jumpToDiffLine(view, blockStart);
            }
        }
    }
}


static void navigateInChangedLine(bool forward)
{
    if (!compareMode)
    {
        showMessage(@"ComparePlus", @"No active comparison.");
        return;
    }

    if (indicatorHighlight < 0)
        return;

    int view = getCurrentViewId();
    intptr_t currentPos = CallScintilla(view, SCI_GETCURRENTPOS, 0, 0);
    intptr_t docLen = CallScintilla(view, SCI_GETLENGTH, 0, 0);

    CallScintilla(view, SCI_SETINDICATORCURRENT, indicatorHighlight, 0);

    if (forward)
    {
        // Find next indicator range
        intptr_t endOfCurrent = CallScintilla(view, SCI_INDICATOREND, indicatorHighlight, currentPos);
        if (endOfCurrent <= currentPos || endOfCurrent >= docLen)
        {
            if (Settings.WrapAround)
                endOfCurrent = 0;
            else
                return;
        }

        intptr_t nextStart = CallScintilla(view, SCI_INDICATORSTART, indicatorHighlight, endOfCurrent);

        // Check if we are actually at an indicator
        int val = (int)CallScintilla(view, SCI_INDICATORVALUEAT, indicatorHighlight, endOfCurrent);
        if (val)
        {
            CallScintilla(view, SCI_GOTOPOS, endOfCurrent, 0);
        }
        else
        {
            // Search forward for the next indicator region
            intptr_t pos = endOfCurrent;
            while (pos < docLen)
            {
                int v = (int)CallScintilla(view, SCI_INDICATORVALUEAT, indicatorHighlight, pos);
                if (v)
                {
                    CallScintilla(view, SCI_GOTOPOS, pos, 0);
                    return;
                }
                pos = CallScintilla(view, SCI_INDICATOREND, indicatorHighlight, pos);
            }
            if (Settings.WrapAround)
            {
                pos = 0;
                while (pos < currentPos)
                {
                    int v = (int)CallScintilla(view, SCI_INDICATORVALUEAT, indicatorHighlight, pos);
                    if (v)
                    {
                        CallScintilla(view, SCI_GOTOPOS, pos, 0);
                        return;
                    }
                    pos = CallScintilla(view, SCI_INDICATOREND, indicatorHighlight, pos);
                }
            }
        }
    }
    else
    {
        // Previous indicator range
        intptr_t startOfCurrent = CallScintilla(view, SCI_INDICATORSTART, indicatorHighlight, currentPos);
        if (startOfCurrent >= currentPos || startOfCurrent <= 0)
        {
            if (Settings.WrapAround)
                startOfCurrent = docLen;
            else
                return;
        }

        // Go backward
        intptr_t pos = startOfCurrent - 1;
        while (pos >= 0)
        {
            int v = (int)CallScintilla(view, SCI_INDICATORVALUEAT, indicatorHighlight, pos);
            if (v)
            {
                intptr_t regionStart = CallScintilla(view, SCI_INDICATORSTART, indicatorHighlight, pos);
                CallScintilla(view, SCI_GOTOPOS, regionStart, 0);
                return;
            }
            intptr_t prevEnd = CallScintilla(view, SCI_INDICATORSTART, indicatorHighlight, pos);
            if (prevEnd >= pos)
                pos--;
            else
                pos = prevEnd - 1;
        }

        if (Settings.WrapAround)
        {
            pos = docLen - 1;
            while (pos > currentPos)
            {
                int v = (int)CallScintilla(view, SCI_INDICATORVALUEAT, indicatorHighlight, pos);
                if (v)
                {
                    intptr_t regionStart = CallScintilla(view, SCI_INDICATORSTART, indicatorHighlight, pos);
                    CallScintilla(view, SCI_GOTOPOS, regionStart, 0);
                    return;
                }
                intptr_t prevEnd = CallScintilla(view, SCI_INDICATORSTART, indicatorHighlight, pos);
                if (prevEnd >= pos)
                    pos--;
                else
                    pos = prevEnd - 1;
            }
        }
    }
}


// =====================================================================
//  Scroll sync
// =====================================================================

static void syncScrollPositions(int changedView)
{
    if (!compareMode || !scrollSyncEnabled || syncingScroll)
        return;

    syncingScroll = true;

    int otherView = getOtherViewId(changedView);
    intptr_t firstVisible = getFirstVisibleLine(changedView);

    // Use the alignment info for accurate sync if available
    if (!activeSummary.alignmentInfo.empty())
    {
        intptr_t docLine = getDocLineFromVisible(changedView, firstVisible);

        // Find matching line in alignment info
        intptr_t matchLine = otherViewMatchingLine(changedView, docLine);
        if (matchLine >= 0)
        {
            intptr_t visibleMatchLine = getVisibleFromDocLine(otherView, matchLine);
            CallScintilla(otherView, SCI_SETFIRSTVISIBLELINE, visibleMatchLine, 0);
        }
        else
        {
            CallScintilla(otherView, SCI_SETFIRSTVISIBLELINE, firstVisible, 0);
        }
    }
    else
    {
        CallScintilla(otherView, SCI_SETFIRSTVISIBLELINE, firstVisible, 0);
    }

    // Also sync horizontal scroll
    intptr_t xOffset = CallScintilla(changedView, SCI_GETXOFFSET, 0, 0);
    CallScintilla(otherView, SCI_SETXOFFSET, xOffset, 0);

    syncingScroll = false;
}


// =====================================================================
//  Diff since last save
// =====================================================================

static void doDiffSinceLastSave()
{
    @autoreleasepool {

    int view = getCurrentViewId();
    intptr_t buffId = getCurrentBuffId();
    std::string filePath = getFilePath(buffId);

    if (filePath.empty())
    {
        showMessage(@"ComparePlus", @"The current file has not been saved yet.");
        return;
    }

    // Read the saved file content
    NSString* nsPath = [NSString stringWithUTF8String:filePath.c_str()];
    NSData* fileData = [NSData dataWithContentsOfFile:nsPath];
    if (!fileData)
    {
        showMessage(@"ComparePlus", @"Cannot read the saved file.");
        return;
    }

    NSString* savedContent = [[NSString alloc] initWithData:fileData encoding:NSUTF8StringEncoding];
    if (!savedContent)
    {
        // Try Latin-1 fallback
        savedContent = [[NSString alloc] initWithData:fileData encoding:NSISOLatin1StringEncoding];
    }
    if (!savedContent)
    {
        showMessage(@"ComparePlus", @"Cannot decode the saved file content.");
        return;
    }

    // Get the current editor content
    intptr_t docLen = CallScintilla(view, SCI_GETLENGTH, 0, 0);
    std::vector<char> currentBuf(docLen + 1);
    CallScintilla(view, SCI_GETTEXT, docLen + 1, (intptr_t)currentBuf.data());
    std::string currentContent(currentBuf.data());

    std::string savedStr = savedContent.UTF8String ?: "";

    if (currentContent == savedStr)
    {
        showMessage(@"ComparePlus", @"No changes since last save.");
        return;
    }

    // Split both into lines
    auto splitLines = [](const std::string& text) -> std::vector<std::string> {
        std::vector<std::string> lines;
        std::istringstream stream(text);
        std::string line;
        while (std::getline(stream, line))
        {
            // Remove \r if present
            if (!line.empty() && line.back() == '\r')
                line.pop_back();
            lines.push_back(line);
        }
        return lines;
    };

    std::vector<std::string> savedLines  = splitLines(savedStr);
    std::vector<std::string> currentLines = splitLines(currentContent);

    // Compute hashes for faster comparison
    std::vector<uint64_t> savedHashes(savedLines.size());
    std::vector<uint64_t> currentHashes(currentLines.size());

    auto hashString = [](const std::string& s) -> uint64_t {
        uint64_t h = 14695981039346656037ULL;
        for (char c : s)
        {
            h ^= (uint64_t)(unsigned char)c;
            h *= 1099511628211ULL;
        }
        return h;
    };

    for (size_t i = 0; i < savedLines.size(); ++i)
        savedHashes[i] = hashString(savedLines[i]);
    for (size_t i = 0; i < currentLines.size(); ++i)
        currentHashes[i] = hashString(currentLines[i]);

    // Run diff
    DiffCalc<uint64_t> dc(savedHashes, currentHashes);
    auto diffs = dc(true, true, true);

    if (diffs.empty())
    {
        showMessage(@"ComparePlus", @"No differences found (hash collision check passed).");
        return;
    }

    // Ensure marker definitions are applied before using them
    applyMarkerColors();

    // Clear any previous compare markers
    clearWindow(view, true);

    // Apply markers to current view only (self-diff mode)
    for (const auto& d : diffs)
    {
        if (d.type == diff_type::DIFF_IN_1)
        {
            // Lines removed from saved version (not present in current)
            // Mark the insertion point
            intptr_t line = d.off;
            if (line >= getLinesCount(view))
                line = getLinesCount(view) - 1;
            if (line >= 0)
                CallScintilla(view, SCI_MARKERADDSET, line, (1 << (markerBaseId + MARKER_REMOVED_LINE)) |
                                                            (1 << (markerBaseId + MARKER_REMOVED_SYMBOL)));
        }
        else if (d.type == diff_type::DIFF_IN_2)
        {
            // Lines added in current version
            for (intptr_t i = 0; i < d.len; ++i)
            {
                intptr_t line = d.off + i;
                if (line < getLinesCount(view))
                {
                    CallScintilla(view, SCI_MARKERADDSET, line,
                        (1 << (markerBaseId + MARKER_ADDED_LINE)) |
                        (1 << (markerBaseId + MARKER_ADDED_SYMBOL)));
                }
            }
        }
    }

    // Set the view to compare mode styling
    setCompareView(view, !Settings.HideMargin, Settings.colors().blank,
                   Settings.colors().caret_line_transparency);

    } // @autoreleasepool
}


// =====================================================================
//  Compare to clipboard
// =====================================================================

static void doCompareToClipboard()
{
    @autoreleasepool {

    int view = getCurrentViewId();

    // Get clipboard content
    NSPasteboard* pb = [NSPasteboard generalPasteboard];
    NSString* clipStr = [pb stringForType:NSPasteboardTypeString];
    if (!clipStr || clipStr.length == 0)
    {
        showMessage(@"ComparePlus", @"The clipboard is empty.");
        return;
    }

    // Get current selection or entire document
    std::string editorContent;
    bool hasSelection = isSelection(view);

    if (hasSelection)
    {
        auto sel = getSelection(view);
        intptr_t selLen = sel.second - sel.first;
        if (selLen > 0)
        {
            auto text = getText(view, sel.first, sel.second);
            editorContent.assign(text.begin(), text.end());
        }
    }
    else
    {
        intptr_t docLen = CallScintilla(view, SCI_GETLENGTH, 0, 0);
        std::vector<char> buf(docLen + 1);
        CallScintilla(view, SCI_GETTEXT, docLen + 1, (intptr_t)buf.data());
        editorContent.assign(buf.data());
    }

    std::string clipContent = clipStr.UTF8String ?: "";

    if (editorContent == clipContent)
    {
        showMessage(@"ComparePlus", @"Content matches the clipboard exactly.");
        return;
    }

    // Split into lines and compare using diff
    auto splitLines = [](const std::string& text) -> std::vector<std::string> {
        std::vector<std::string> lines;
        std::istringstream stream(text);
        std::string line;
        while (std::getline(stream, line))
        {
            if (!line.empty() && line.back() == '\r')
                line.pop_back();
            lines.push_back(line);
        }
        return lines;
    };

    auto editorLines = splitLines(editorContent);
    auto clipLines   = splitLines(clipContent);

    auto hashString = [](const std::string& s) -> uint64_t {
        uint64_t h = 14695981039346656037ULL;
        for (char c : s)
        {
            h ^= (uint64_t)(unsigned char)c;
            h *= 1099511628211ULL;
        }
        return h;
    };

    std::vector<uint64_t> editorHashes(editorLines.size());
    std::vector<uint64_t> clipHashes(clipLines.size());

    for (size_t i = 0; i < editorLines.size(); ++i)
        editorHashes[i] = hashString(editorLines[i]);
    for (size_t i = 0; i < clipLines.size(); ++i)
        clipHashes[i] = hashString(clipLines[i]);

    DiffCalc<uint64_t> dc(editorHashes, clipHashes);
    auto diffs = dc(true, true, true);

    // Build summary message
    intptr_t added = 0, removed = 0, changed = 0;
    for (size_t i = 0; i < diffs.size(); ++i)
    {
        if (diffs[i].type == diff_type::DIFF_IN_1)
        {
            if (i + 1 < diffs.size() && diffs[i + 1].type == diff_type::DIFF_IN_2)
            {
                changed += std::min(diffs[i].len, diffs[i + 1].len);
                ++i;
            }
            else
            {
                removed += diffs[i].len;
            }
        }
        else if (diffs[i].type == diff_type::DIFF_IN_2)
        {
            added += diffs[i].len;
        }
    }

    // Ensure marker definitions are applied before using them
    applyMarkerColors();

    // Mark lines in editor
    clearWindow(view, true);

    intptr_t baseLineOffset = 0;
    if (hasSelection)
    {
        auto sel = getSelection(view);
        baseLineOffset = CallScintilla(view, SCI_LINEFROMPOSITION, sel.first, 0);
    }

    for (const auto& d : diffs)
    {
        if (d.type == diff_type::DIFF_IN_1)
        {
            // Lines in editor not in clipboard (will show as "removed from clipboard perspective")
            for (intptr_t i = 0; i < d.len; ++i)
            {
                intptr_t line = baseLineOffset + d.off + i;
                if (line < getLinesCount(view))
                {
                    CallScintilla(view, SCI_MARKERADDSET, line,
                        (1 << (markerBaseId + MARKER_REMOVED_LINE)) |
                        (1 << (markerBaseId + MARKER_REMOVED_SYMBOL)));
                }
            }
        }
        else if (d.type == diff_type::DIFF_IN_2)
        {
            // Lines in clipboard not in editor (show at insertion point)
            intptr_t line = baseLineOffset + d.off;
            if (line >= getLinesCount(view))
                line = getLinesCount(view) - 1;
            if (line >= 0)
            {
                CallScintilla(view, SCI_MARKERADDSET, line,
                    (1 << (markerBaseId + MARKER_ADDED_LINE)) |
                    (1 << (markerBaseId + MARKER_ADDED_SYMBOL)));
            }
        }
    }

    setCompareView(view, !Settings.HideMargin, Settings.colors().blank,
                   Settings.colors().caret_line_transparency);

    showMessage(@"ComparePlus",
        [NSString stringWithFormat:@"Comparison with Clipboard:\n\n"
            @"Changed lines: %lld\n"
            @"Lines only in file: %lld\n"
            @"Lines only in clipboard: %lld",
            (long long)changed, (long long)removed, (long long)added]);

    } // @autoreleasepool
}


// =====================================================================
//  Menu command callbacks
// =====================================================================



static void cmdCompare()
{
    doCompare(false, false);
}


static void cmdCompareSelections()
{
    // The active tab has a selection. Capture LINE NUMBERS before the move.
    int view = getCurrentViewId();

    if (!isSelection(view))
    {
        showMessage(@"ComparePlus", @"Please select text in both files to compare selections.");
        return;
    }

    // Capture active tab's selection as line numbers (this tab will become SUB_VIEW)
    auto movedSel = getSelectionLines(view);

    // Move active tab to split view
    hostAction(@selector(moveToOtherVerticalView:));

    // Now the other file is active in MAIN_VIEW. Check it has a selection.
    if (!isSelection(MAIN_VIEW))
    {
        showMessage(@"ComparePlus", @"Please select text in both files to compare selections.");
        hostAction(@selector(resetView:));
        return;
    }

    // Capture the remaining tab's selection (now in MAIN_VIEW)
    auto mainSel = getSelectionLines(MAIN_VIEW);

    // Store pre-captured selections so doCompare uses them instead of re-reading
    savedSelectionMain = mainSel;
    savedSelectionSub  = movedSel;

    // Run compare in selection mode — skip the move (already done above)
    // Sync scrolling is enabled by doCompare after alignment completes
    doCompare(true, false, true);

    // Clear saved selections
    savedSelectionMain = {-1, -1};
    savedSelectionSub  = {-1, -1};
}


static void cmdFindUniqueLines()
{
    doCompare(false, true);
}


static void cmdFindUniqueLinesInSel()
{
    int view = getCurrentViewId();
    int otherView = getOtherViewId(view);

    if (!isSelection(view) || !isSelection(otherView))
    {
        showMessage(@"ComparePlus", @"Please select text in both views to find unique lines.");
        return;
    }
    doCompare(true, true);
}


static void cmdDiffSinceLastSave()
{
    doDiffSinceLastSave();
}


static void cmdCompareToClipboard()
{
    doCompareToClipboard();
}


static void cmdSVNDiff()
{
    showMessage(@"ComparePlus", @"SVN Diff is not yet available in the macOS version.");
}


static void cmdGitDiff()
{
    showMessage(@"ComparePlus", @"Git Diff is not yet available in the macOS version.");
}


static void cmdClearActiveCompare()
{
    if (!compareMode)
        return;

    // Step 1: Clear all compare markers and annotations
    clearAllCompares();

    // Step 2: Turn off scroll sync explicitly (before reset collapses the split)
    hostAction(@selector(disableSyncScrolling:));

    // Step 3: Reset View — moves all secondary tabs back, collapses split
    hostAction(@selector(resetView:));
}


static void cmdClearAllCompares()
{
    cmdClearActiveCompare();
}


static void cmdPrevDiffBlock()
{
    navigateToDiff(false, false);
}


static void cmdNextDiffBlock()
{
    navigateToDiff(true, false);
}


static void cmdFirstDiffBlock()
{
    navigateToDiff(false, true);
}


static void cmdLastDiffBlock()
{
    navigateToDiff(true, true);
}


static void cmdPrevDiffInChangedLine()
{
    navigateInChangedLine(false);
}


static void cmdNextDiffInChangedLine()
{
    navigateInChangedLine(true);
}


static void cmdActiveCompareSummary()
{
    if (!compareMode)
    {
        showMessage(@"ComparePlus", @"No active comparison.");
        return;
    }

    @autoreleasepool {
    NSString* summary = [NSString stringWithFormat:
        @"Active Compare Summary\n\n"
        @"Total diff lines: %lld\n"
        @"Added: %lld\n"
        @"Removed: %lld\n"
        @"Changed: %lld\n"
        @"Moved: %lld\n"
        @"Matching: %lld",
        (long long)activeSummary.diffLines,
        (long long)activeSummary.added,
        (long long)activeSummary.removed,
        (long long)activeSummary.changed,
        (long long)activeSummary.moved,
        (long long)activeSummary.match];

    showMessage(@"Compare Summary", summary);
    }
}


static void cmdCopyVisibleLines()
{
    @autoreleasepool {

    if (!compareMode)
    {
        showMessage(@"ComparePlus", @"No active comparison.");
        return;
    }

    int view = getCurrentViewId();
    std::vector<intptr_t> visibleLines = getVisibleLines(view);

    NSMutableString* result = [NSMutableString string];

    for (intptr_t line : visibleLines)
    {
        auto text = getLineText(view, line, true);
        if (!text.empty())
        {
            NSString* lineStr = [[NSString alloc] initWithBytes:text.data()
                                                         length:text.size()
                                                       encoding:NSUTF8StringEncoding];
            if (lineStr)
                [result appendString:lineStr];
        }
    }

    NSPasteboard* pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:result forType:NSPasteboardTypeString];

    } // @autoreleasepool
}


static void cmdDeleteVisibleLines()
{
    if (!compareMode)
    {
        showMessage(@"ComparePlus", @"No active comparison.");
        return;
    }

    int view = getCurrentViewId();
    std::vector<intptr_t> visibleLines = getVisibleLines(view);

    if (visibleLines.empty())
        return;

    ScopedViewUndoAction undoAction(view);

    // Delete from bottom to top to preserve line numbers
    for (auto it = visibleLines.rbegin(); it != visibleLines.rend(); ++it)
    {
        intptr_t line = *it;
        if (line < getLinesCount(view))
            deleteLine(view, line);
    }
}


static void cmdBookmarkVisibleLines()
{
    if (!compareMode)
    {
        showMessage(@"ComparePlus", @"No active comparison.");
        return;
    }

    int view = getCurrentViewId();
    int markMask = MARKER_MASK_LINE;
    bookmarkMarkedLines(view, markMask);
}


static void cmdCompareOptions()
{
    showCompareOptionsDialog();
}


static void cmdBookmarksAsSyncPoints()
{
    bookmarksAsSyncPoints = !bookmarksAsSyncPoints;
    Settings.BookmarksAsSync = bookmarksAsSyncPoints;
    Settings.markAsDirty();
    updateMenuChecks();
}


static void cmdDiffsVisualFilters()
{
    showDiffsVisualFiltersDialog();
}


static void cmdNavigationBar()
{
    navBarVisible = !navBarVisible;
    Settings.ShowNavBar = navBarVisible;
    Settings.markAsDirty();
    updateMenuChecks();
}


static void cmdAutoRecompare()
{
    autoRecompareEnabled = !autoRecompareEnabled;
    Settings.RecompareOnChange = autoRecompareEnabled;
    Settings.markAsDirty();
    updateMenuChecks();
}


static void cmdSettings()
{
    showSettingsDialog();
}


static void cmdHelpAbout()
{
    showAboutDialog();
}


// =====================================================================
//  Menu check state management
// =====================================================================

static void updateMenuChecks()
{
    // Menu item indices for checkmark items
    // 28 = Bookmarks as Sync (index 28 in funcItem)
    // 31 = Navigation Bar (index 31)
    // 32 = Auto Re-Compare (index 32)

    // These cmdIDs are assigned by the host at load time
    nppData._sendMessage(nppData._nppHandle, NPPM_SETMENUITEMCHECK,
        funcItem[28]._cmdID, bookmarksAsSyncPoints ? 1 : 0);
    nppData._sendMessage(nppData._nppHandle, NPPM_SETMENUITEMCHECK,
        funcItem[31]._cmdID, navBarVisible ? 1 : 0);
    nppData._sendMessage(nppData._nppHandle, NPPM_SETMENUITEMCHECK,
        funcItem[32]._cmdID, autoRecompareEnabled ? 1 : 0);
}


// =====================================================================
//  BGR color <-> NSColor conversion helpers
// =====================================================================

static NSColor* bgrToNSColor(int bgr)
{
    CGFloat r = (CGFloat)(bgr & 0xFF) / 255.0;
    CGFloat g = (CGFloat)((bgr >> 8) & 0xFF) / 255.0;
    CGFloat b = (CGFloat)((bgr >> 16) & 0xFF) / 255.0;
    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0];
}


static int nsColorToBGR(NSColor* color)
{
    NSColor* c = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (!c) c = color;
    int r = (int)(c.redComponent * 255.0);
    int g = (int)(c.greenComponent * 255.0);
    int b = (int)(c.blueComponent * 255.0);
    return (b << 16) | (g << 8) | r;
}


// =====================================================================
//  Settings Dialog  --  three-column layout matching Windows
// =====================================================================

static void showSettingsDialog()
{
    @autoreleasepool {

    NSPanel* panel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, 780, 530)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    panel.title = @"ComparePlus Settings";
    [panel center];

    NSView* cv = panel.contentView;
    CGFloat pad = 12;

    // ── LEFT COLUMN: Main Settings ──

    NSBox* mainBox = [[NSBox alloc] initWithFrame:NSMakeRect(pad, 200, 230, 320)];
    mainBox.title = @"Main Settings";
    mainBox.titlePosition = NSAtTop;
    [cv addSubview:mainBox];
    NSView* mainContent = mainBox.contentView;

    CGFloat y = 270;
    CGFloat lineH = 22;

    // Set as First: New / Old radio
    NSTextField* lblFirst = [NSTextField labelWithString:@"Set as First to Compare:"];
    lblFirst.frame = NSMakeRect(8, y, 200, 16);
    [mainContent addSubview:lblFirst];
    y -= lineH;

    NSButton* radioFirstNew = [NSButton radioButtonWithTitle:@"New file" target:nil action:nil];
    radioFirstNew.frame = NSMakeRect(20, y, 90, 18);
    radioFirstNew.state = Settings.FirstFileIsNew ? NSControlStateValueOn : NSControlStateValueOff;
    [mainContent addSubview:radioFirstNew];

    NSButton* radioFirstOld = [NSButton radioButtonWithTitle:@"Old file" target:nil action:nil];
    radioFirstOld.frame = NSMakeRect(115, y, 90, 18);
    radioFirstOld.state = Settings.FirstFileIsNew ? NSControlStateValueOff : NSControlStateValueOn;
    [mainContent addSubview:radioFirstOld];
    y -= lineH + 6;

    // Files Position radio
    NSTextField* lblPos = [NSTextField labelWithString:@"Files Position:"];
    lblPos.frame = NSMakeRect(8, y, 200, 16);
    [mainContent addSubview:lblPos];
    y -= lineH;

    NSButton* radioPosMain = [NSButton radioButtonWithTitle:@"New in Main" target:nil action:nil];
    radioPosMain.frame = NSMakeRect(20, y, 100, 18);
    radioPosMain.state = (Settings.NewFileViewId == MAIN_VIEW) ? NSControlStateValueOn : NSControlStateValueOff;
    [mainContent addSubview:radioPosMain];

    NSButton* radioPosSub = [NSButton radioButtonWithTitle:@"New in Sub" target:nil action:nil];
    radioPosSub.frame = NSMakeRect(125, y, 100, 18);
    radioPosSub.state = (Settings.NewFileViewId == SUB_VIEW) ? NSControlStateValueOn : NSControlStateValueOff;
    [mainContent addSubview:radioPosSub];
    y -= lineH + 6;

    // Compare to Prev radio
    NSTextField* lblCmpTo = [NSTextField labelWithString:@"Default Compare in Single-View:"];
    lblCmpTo.frame = NSMakeRect(8, y, 210, 16);
    [mainContent addSubview:lblCmpTo];
    y -= lineH;

    NSButton* radioPrev = [NSButton radioButtonWithTitle:@"Previous" target:nil action:nil];
    radioPrev.frame = NSMakeRect(20, y, 90, 18);
    radioPrev.state = Settings.CompareToPrev ? NSControlStateValueOn : NSControlStateValueOff;
    [mainContent addSubview:radioPrev];

    NSButton* radioNext = [NSButton radioButtonWithTitle:@"Next" target:nil action:nil];
    radioNext.frame = NSMakeRect(115, y, 90, 18);
    radioNext.state = Settings.CompareToPrev ? NSControlStateValueOff : NSControlStateValueOn;
    [mainContent addSubview:radioNext];
    y -= lineH + 6;

    // Status bar info radio
    NSTextField* lblStatus = [NSTextField labelWithString:@"Compare StatusBar Info:"];
    lblStatus.frame = NSMakeRect(8, y, 200, 16);
    [mainContent addSubview:lblStatus];
    y -= lineH;

    NSButton* radioStatSummary = [NSButton radioButtonWithTitle:@"Diffs Summary" target:nil action:nil];
    radioStatSummary.frame = NSMakeRect(20, y, 120, 18);
    radioStatSummary.state = (Settings.StatusInfo == DIFFS_SUMMARY) ? NSControlStateValueOn : NSControlStateValueOff;
    [mainContent addSubview:radioStatSummary];
    y -= lineH;

    NSButton* radioStatOptions = [NSButton radioButtonWithTitle:@"Compare Options" target:nil action:nil];
    radioStatOptions.frame = NSMakeRect(20, y, 120, 18);
    radioStatOptions.state = (Settings.StatusInfo == COMPARE_OPTIONS) ? NSControlStateValueOn : NSControlStateValueOff;
    [mainContent addSubview:radioStatOptions];
    y -= lineH;

    NSButton* radioStatNone = [NSButton radioButtonWithTitle:@"Disabled" target:nil action:nil];
    radioStatNone.frame = NSMakeRect(20, y, 120, 18);
    radioStatNone.state = (Settings.StatusInfo == STATUS_DISABLED) ? NSControlStateValueOn : NSControlStateValueOff;
    [mainContent addSubview:radioStatNone];

    // ── MIDDLE COLUMN: Misc. ──

    NSBox* miscBox = [[NSBox alloc] initWithFrame:NSMakeRect(pad + 240, 200, 250, 320)];
    miscBox.title = @"Misc.";
    miscBox.titlePosition = NSAtTop;
    [cv addSubview:miscBox];
    NSView* miscContent = miscBox.contentView;

    y = 270;

    NSButton* chkEncCheck = [NSButton checkboxWithTitle:@"Warn about encoding mismatch" target:nil action:nil];
    chkEncCheck.frame = NSMakeRect(8, y, 230, 18);
    chkEncCheck.state = Settings.EncodingsCheck ? NSControlStateValueOn : NSControlStateValueOff;
    [miscContent addSubview:chkEncCheck];
    y -= lineH;

    NSButton* chkSizeCheck = [NSButton checkboxWithTitle:@"Warn about big files" target:nil action:nil];
    chkSizeCheck.frame = NSMakeRect(8, y, 230, 18);
    chkSizeCheck.state = Settings.SizesCheck ? NSControlStateValueOn : NSControlStateValueOff;
    [miscContent addSubview:chkSizeCheck];
    y -= lineH;

    NSButton* chkSyncCheck = [NSButton checkboxWithTitle:@"Warn about sync point mismatch" target:nil action:nil];
    chkSyncCheck.frame = NSMakeRect(8, y, 230, 18);
    chkSyncCheck.state = Settings.ManualSyncCheck ? NSControlStateValueOn : NSControlStateValueOff;
    [miscContent addSubview:chkSyncCheck];
    y -= lineH + 6;

    NSButton* chkCloseOnMatch = [NSButton checkboxWithTitle:@"Prompt to close on match" target:nil action:nil];
    chkCloseOnMatch.frame = NSMakeRect(8, y, 230, 18);
    chkCloseOnMatch.state = Settings.PromptToCloseOnMatch ? NSControlStateValueOn : NSControlStateValueOff;
    [miscContent addSubview:chkCloseOnMatch];
    y -= lineH;

    NSButton* chkHideMargin = [NSButton checkboxWithTitle:@"Hide compare margin" target:nil action:nil];
    chkHideMargin.frame = NSMakeRect(8, y, 230, 18);
    chkHideMargin.state = Settings.HideMargin ? NSControlStateValueOn : NSControlStateValueOff;
    [miscContent addSubview:chkHideMargin];
    y -= lineH;

    NSButton* chkNeverColor = [NSButton checkboxWithTitle:@"Never colorize ignored lines" target:nil action:nil];
    chkNeverColor.frame = NSMakeRect(8, y, 230, 18);
    chkNeverColor.state = Settings.NeverMarkIgnored ? NSControlStateValueOn : NSControlStateValueOff;
    [miscContent addSubview:chkNeverColor];
    y -= lineH + 6;

    NSButton* chkFollowCaret = [NSButton checkboxWithTitle:@"Follow caret" target:nil action:nil];
    chkFollowCaret.frame = NSMakeRect(8, y, 230, 18);
    chkFollowCaret.state = Settings.FollowingCaret ? NSControlStateValueOn : NSControlStateValueOff;
    [miscContent addSubview:chkFollowCaret];
    y -= lineH;

    NSButton* chkWrapAround = [NSButton checkboxWithTitle:@"Wrap around" target:nil action:nil];
    chkWrapAround.frame = NSMakeRect(8, y, 230, 18);
    chkWrapAround.state = Settings.WrapAround ? NSControlStateValueOn : NSControlStateValueOff;
    [miscContent addSubview:chkWrapAround];
    y -= lineH;

    NSButton* chkGotoFirst = [NSButton checkboxWithTitle:@"Go to first diff on recompare" target:nil action:nil];
    chkGotoFirst.frame = NSMakeRect(8, y, 230, 18);
    chkGotoFirst.state = Settings.GotoFirstDiff ? NSControlStateValueOn : NSControlStateValueOff;
    [miscContent addSubview:chkGotoFirst];

    // ── RIGHT COLUMN: Color and Highlight Settings ──

    NSBox* colorBox = [[NSBox alloc] initWithFrame:NSMakeRect(pad + 500, 200, 260, 320)];
    colorBox.title = @"Color and Highlight Settings";
    colorBox.titlePosition = NSAtTop;
    [cv addSubview:colorBox];
    NSView* colorContent = colorBox.contentView;

    ColorSettings& colors = Settings.colors();

    struct ColorItem {
        const char* label;
        int* colorRef;
    };

    ColorItem colorItems[] = {
        { "Added line",         &colors.added },
        { "Removed line",       &colors.removed },
        { "Moved line",         &colors.moved },
        { "Changed line",       &colors.changed },
        { "Added highlight",    &colors.added_part },
        { "Removed highlight",  &colors.removed_part },
        { "Moved highlight",    &colors.moved_part },
    };

    y = 260;
    NSMutableArray* colorWells = [NSMutableArray array];

    for (int i = 0; i < 7; ++i)
    {
        NSTextField* lbl = [NSTextField labelWithString:
            [NSString stringWithUTF8String:colorItems[i].label]];
        lbl.frame = NSMakeRect(8, y, 130, 16);
        [colorContent addSubview:lbl];

        NSColorWell* well = [[NSColorWell alloc] initWithFrame:NSMakeRect(145, y - 2, 40, 20)];
        well.color = bgrToNSColor(*colorItems[i].colorRef);
        well.tag = i;
        [colorContent addSubview:well];
        [colorWells addObject:well];

        y -= (lineH + 6);
    }

    // Transparency spinners
    y -= 8;

    NSTextField* lblPartTransp = [NSTextField labelWithString:@"Highlight transparency:"];
    lblPartTransp.frame = NSMakeRect(8, y, 150, 16);
    [colorContent addSubview:lblPartTransp];

    NSTextField* txtPartTransp = [[NSTextField alloc] initWithFrame:NSMakeRect(160, y - 2, 40, 20)];
    txtPartTransp.intValue = colors.part_transparency;
    [colorContent addSubview:txtPartTransp];

    NSStepper* stepPartTransp = [[NSStepper alloc] initWithFrame:NSMakeRect(202, y - 2, 20, 20)];
    stepPartTransp.minValue = 0;
    stepPartTransp.maxValue = 255;
    stepPartTransp.intValue = colors.part_transparency;
    [colorContent addSubview:stepPartTransp];
    y -= (lineH + 4);

    NSTextField* lblCaretTransp = [NSTextField labelWithString:@"Caret line transparency:"];
    lblCaretTransp.frame = NSMakeRect(8, y, 155, 16);
    [colorContent addSubview:lblCaretTransp];

    NSTextField* txtCaretTransp = [[NSTextField alloc] initWithFrame:NSMakeRect(160, y - 2, 40, 20)];
    txtCaretTransp.intValue = colors.caret_line_transparency;
    [colorContent addSubview:txtCaretTransp];

    NSStepper* stepCaretTransp = [[NSStepper alloc] initWithFrame:NSMakeRect(202, y - 2, 20, 20)];
    stepCaretTransp.minValue = 0;
    stepCaretTransp.maxValue = 255;
    stepCaretTransp.intValue = colors.caret_line_transparency;
    [colorContent addSubview:stepCaretTransp];
    y -= (lineH + 4);

    // Resemblance percentage
    NSTextField* lblResembl = [NSTextField labelWithString:@"Resemblance %:"];
    lblResembl.frame = NSMakeRect(8, y, 130, 16);
    [colorContent addSubview:lblResembl];

    NSTextField* txtResembl = [[NSTextField alloc] initWithFrame:NSMakeRect(160, y - 2, 40, 20)];
    txtResembl.intValue = Settings.ChangedResemblPercent;
    [colorContent addSubview:txtResembl];

    NSStepper* stepResembl = [[NSStepper alloc] initWithFrame:NSMakeRect(202, y - 2, 20, 20)];
    stepResembl.minValue = 0;
    stepResembl.maxValue = 100;
    stepResembl.intValue = Settings.ChangedResemblPercent;
    [colorContent addSubview:stepResembl];

    // ── BOTTOM ROW: Toolbar Settings ──

    NSBox* tbBox = [[NSBox alloc] initWithFrame:NSMakeRect(pad, 100, 750, 90)];
    tbBox.title = @"Toolbar Settings";
    tbBox.titlePosition = NSAtTop;
    [cv addSubview:tbBox];
    NSView* tbContent = tbBox.contentView;

    NSButton* chkEnableTB = [NSButton checkboxWithTitle:@"Enable Toolbar" target:nil action:nil];
    chkEnableTB.frame = NSMakeRect(8, 40, 130, 18);
    chkEnableTB.state = Settings.EnableToolbar ? NSControlStateValueOn : NSControlStateValueOff;
    [tbContent addSubview:chkEnableTB];

    NSButton* chkSetFirstTB = [NSButton checkboxWithTitle:@"Set as First" target:nil action:nil];
    chkSetFirstTB.frame = NSMakeRect(145, 40, 100, 18);
    chkSetFirstTB.state = Settings.SetAsFirstTB ? NSControlStateValueOn : NSControlStateValueOff;
    [tbContent addSubview:chkSetFirstTB];

    NSButton* chkCompareTB = [NSButton checkboxWithTitle:@"Compare" target:nil action:nil];
    chkCompareTB.frame = NSMakeRect(250, 40, 80, 18);
    chkCompareTB.state = Settings.CompareTB ? NSControlStateValueOn : NSControlStateValueOff;
    [tbContent addSubview:chkCompareTB];

    NSButton* chkCompareSelTB = [NSButton checkboxWithTitle:@"Sel Compare" target:nil action:nil];
    chkCompareSelTB.frame = NSMakeRect(340, 40, 110, 18);
    chkCompareSelTB.state = Settings.CompareSelTB ? NSControlStateValueOn : NSControlStateValueOff;
    [tbContent addSubview:chkCompareSelTB];

    NSButton* chkClearTB = [NSButton checkboxWithTitle:@"Clear" target:nil action:nil];
    chkClearTB.frame = NSMakeRect(455, 40, 60, 18);
    chkClearTB.state = Settings.ClearCompareTB ? NSControlStateValueOn : NSControlStateValueOff;
    [tbContent addSubview:chkClearTB];

    NSButton* chkNavTB = [NSButton checkboxWithTitle:@"Navigation" target:nil action:nil];
    chkNavTB.frame = NSMakeRect(520, 40, 100, 18);
    chkNavTB.state = Settings.NavigationTB ? NSControlStateValueOn : NSControlStateValueOff;
    [tbContent addSubview:chkNavTB];

    NSButton* chkDiffFilterTB = [NSButton checkboxWithTitle:@"Diffs Filter" target:nil action:nil];
    chkDiffFilterTB.frame = NSMakeRect(625, 40, 100, 18);
    chkDiffFilterTB.state = Settings.DiffsFilterTB ? NSControlStateValueOn : NSControlStateValueOff;
    [tbContent addSubview:chkDiffFilterTB];

    // ── OK / Cancel / Reset Defaults ──

    NSButton* btnReset = [[NSButton alloc] initWithFrame:NSMakeRect(pad, 55, 130, 28)];
    btnReset.title = @"Reset to Defaults";
    btnReset.bezelStyle = NSBezelStyleRounded;
    [cv addSubview:btnReset];

    NSButton* btnOK = [[NSButton alloc] initWithFrame:NSMakeRect(590, 55, 80, 28)];
    btnOK.title = @"OK";
    btnOK.bezelStyle = NSBezelStyleRounded;
    btnOK.keyEquivalent = @"\r";
    btnOK.target = NSApp;
    btnOK.action = @selector(stopModal);
    [cv addSubview:btnOK];

    NSButton* btnCancel = [[NSButton alloc] initWithFrame:NSMakeRect(682, 55, 80, 28)];
    btnCancel.title = @"Cancel";
    btnCancel.bezelStyle = NSBezelStyleRounded;
    btnCancel.keyEquivalent = @"\033";
    btnCancel.target = NSApp;
    btnCancel.action = @selector(abortModal);
    [cv addSubview:btnCancel];

    // ── Reset handler ──

    __block bool resetClicked = false;
    btnReset.target = nil;
    btnReset.action = nil;

    // Use a simple flag approach: clicking reset = special stop code
    // We handle it by checking after modal exits
    // For simplicity, attach a block-based action
    class ResetHelper {
    public:
        static void resetAction(id sender) {
            [NSApp stopModalWithCode:42];
        }
    };
    btnReset.target = NSApp;
    btnReset.action = @selector(stopModal);  // We'll check the response code differently

    NSModalResponse resp = [NSApp runModalForWindow:panel];
    [panel orderOut:nil];

    // Close any open color panels
    if ([NSColorPanel sharedColorPanelExists])
        [[NSColorPanel sharedColorPanel] orderOut:nil];

    if (resp == NSModalResponseStop)
    {
        // Apply settings from controls
        Settings.FirstFileIsNew       = (radioFirstNew.state == NSControlStateValueOn);
        Settings.NewFileViewId        = (radioPosMain.state == NSControlStateValueOn) ? MAIN_VIEW : SUB_VIEW;
        Settings.CompareToPrev        = (radioPrev.state == NSControlStateValueOn);

        if (radioStatSummary.state == NSControlStateValueOn)
            Settings.StatusInfo = DIFFS_SUMMARY;
        else if (radioStatOptions.state == NSControlStateValueOn)
            Settings.StatusInfo = COMPARE_OPTIONS;
        else
            Settings.StatusInfo = STATUS_DISABLED;

        Settings.EncodingsCheck       = (chkEncCheck.state == NSControlStateValueOn);
        Settings.SizesCheck           = (chkSizeCheck.state == NSControlStateValueOn);
        Settings.ManualSyncCheck      = (chkSyncCheck.state == NSControlStateValueOn);
        Settings.PromptToCloseOnMatch = (chkCloseOnMatch.state == NSControlStateValueOn);
        Settings.HideMargin           = (chkHideMargin.state == NSControlStateValueOn);
        Settings.NeverMarkIgnored     = (chkNeverColor.state == NSControlStateValueOn);
        Settings.FollowingCaret       = (chkFollowCaret.state == NSControlStateValueOn);
        Settings.WrapAround           = (chkWrapAround.state == NSControlStateValueOn);
        Settings.GotoFirstDiff        = (chkGotoFirst.state == NSControlStateValueOn);

        // Read color wells
        ColorItem colorItemsCopy[] = {
            { "Added line",         &colors.added },
            { "Removed line",       &colors.removed },
            { "Moved line",         &colors.moved },
            { "Changed line",       &colors.changed },
            { "Added highlight",    &colors.added_part },
            { "Removed highlight",  &colors.removed_part },
            { "Moved highlight",    &colors.moved_part },
        };

        for (int i = 0; i < 7; ++i)
        {
            NSColorWell* well = colorWells[i];
            *colorItemsCopy[i].colorRef = nsColorToBGR(well.color);
        }

        colors.part_transparency         = txtPartTransp.intValue;
        colors.caret_line_transparency   = txtCaretTransp.intValue;
        Settings.ChangedResemblPercent   = txtResembl.intValue;

        // Toolbar settings
        Settings.EnableToolbar  = (chkEnableTB.state == NSControlStateValueOn);
        Settings.SetAsFirstTB   = (chkSetFirstTB.state == NSControlStateValueOn);
        Settings.CompareTB      = (chkCompareTB.state == NSControlStateValueOn);
        Settings.CompareSelTB   = (chkCompareSelTB.state == NSControlStateValueOn);
        Settings.ClearCompareTB = (chkClearTB.state == NSControlStateValueOn);
        Settings.NavigationTB   = (chkNavTB.state == NSControlStateValueOn);
        Settings.DiffsFilterTB  = (chkDiffFilterTB.state == NSControlStateValueOn);

        Settings.markAsDirty();
        Settings.save();

        // Re-apply marker colors if compare is active
        if (compareMode)
        {
            applyMarkerColors();
            setStyles(Settings);
        }
    }

    } // @autoreleasepool
}


// =====================================================================
//  Compare Options Dialog
// =====================================================================

static void showCompareOptionsDialog()
{
    @autoreleasepool {

    NSPanel* panel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, 480, 440)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    panel.title = @"Compare Options";
    [panel center];

    NSView* cv = panel.contentView;
    CGFloat pad = 12;
    CGFloat lineH = 22;

    // ── Detect Options ──

    NSBox* detectBox = [[NSBox alloc] initWithFrame:NSMakeRect(pad, 240, 220, 188)];
    detectBox.title = @"Detect";
    detectBox.titlePosition = NSAtTop;
    [cv addSubview:detectBox];
    NSView* detectContent = detectBox.contentView;

    CGFloat y = 140;

    NSButton* chkMoves = [NSButton checkboxWithTitle:@"Moves" target:nil action:nil];
    chkMoves.frame = NSMakeRect(8, y, 200, 18);
    chkMoves.state = Settings.DetectMoves ? NSControlStateValueOn : NSControlStateValueOff;
    [detectContent addSubview:chkMoves];
    y -= lineH;

    NSButton* chkSubBlock = [NSButton checkboxWithTitle:@"Sub-block diffs" target:nil action:nil];
    chkSubBlock.frame = NSMakeRect(8, y, 200, 18);
    chkSubBlock.state = Settings.DetectSubBlockDiffs ? NSControlStateValueOn : NSControlStateValueOff;
    [detectContent addSubview:chkSubBlock];
    y -= lineH;

    NSButton* chkSubLine = [NSButton checkboxWithTitle:@"Sub-line moves" target:nil action:nil];
    chkSubLine.frame = NSMakeRect(8, y, 200, 18);
    chkSubLine.state = Settings.DetectSubLineMoves ? NSControlStateValueOn : NSControlStateValueOff;
    [detectContent addSubview:chkSubLine];
    y -= lineH;

    NSButton* chkCharDiffs = [NSButton checkboxWithTitle:@"Character diffs" target:nil action:nil];
    chkCharDiffs.frame = NSMakeRect(8, y, 200, 18);
    chkCharDiffs.state = Settings.DetectCharDiffs ? NSControlStateValueOn : NSControlStateValueOff;
    [detectContent addSubview:chkCharDiffs];

    // ── Ignore Options ──

    NSBox* ignoreBox = [[NSBox alloc] initWithFrame:NSMakeRect(pad + 230, 160, 230, 268)];
    ignoreBox.title = @"Ignore";
    ignoreBox.titlePosition = NSAtTop;
    [cv addSubview:ignoreBox];
    NSView* ignoreContent = ignoreBox.contentView;

    y = 220;

    NSButton* chkEmpty = [NSButton checkboxWithTitle:@"Empty lines" target:nil action:nil];
    chkEmpty.frame = NSMakeRect(8, y, 210, 18);
    chkEmpty.state = Settings.IgnoreEmptyLines ? NSControlStateValueOn : NSControlStateValueOff;
    [ignoreContent addSubview:chkEmpty];
    y -= lineH;

    NSButton* chkFolded = [NSButton checkboxWithTitle:@"Folded lines" target:nil action:nil];
    chkFolded.frame = NSMakeRect(8, y, 210, 18);
    chkFolded.state = Settings.IgnoreFoldedLines ? NSControlStateValueOn : NSControlStateValueOff;
    [ignoreContent addSubview:chkFolded];
    y -= lineH;

    NSButton* chkHidden = [NSButton checkboxWithTitle:@"Hidden lines" target:nil action:nil];
    chkHidden.frame = NSMakeRect(8, y, 210, 18);
    chkHidden.state = Settings.IgnoreHiddenLines ? NSControlStateValueOn : NSControlStateValueOff;
    [ignoreContent addSubview:chkHidden];
    y -= lineH;

    NSButton* chkChgSpaces = [NSButton checkboxWithTitle:@"Changed spaces" target:nil action:nil];
    chkChgSpaces.frame = NSMakeRect(8, y, 210, 18);
    chkChgSpaces.state = Settings.IgnoreChangedSpaces ? NSControlStateValueOn : NSControlStateValueOff;
    [ignoreContent addSubview:chkChgSpaces];
    y -= lineH;

    NSButton* chkAllSpaces = [NSButton checkboxWithTitle:@"All spaces" target:nil action:nil];
    chkAllSpaces.frame = NSMakeRect(8, y, 210, 18);
    chkAllSpaces.state = Settings.IgnoreAllSpaces ? NSControlStateValueOn : NSControlStateValueOff;
    [ignoreContent addSubview:chkAllSpaces];
    y -= lineH;

    NSButton* chkEOL = [NSButton checkboxWithTitle:@"End of line" target:nil action:nil];
    chkEOL.frame = NSMakeRect(8, y, 210, 18);
    chkEOL.state = Settings.IgnoreEOL ? NSControlStateValueOn : NSControlStateValueOff;
    [ignoreContent addSubview:chkEOL];
    y -= lineH;

    NSButton* chkCase = [NSButton checkboxWithTitle:@"Case" target:nil action:nil];
    chkCase.frame = NSMakeRect(8, y, 210, 18);
    chkCase.state = Settings.IgnoreCase ? NSControlStateValueOn : NSControlStateValueOff;
    [ignoreContent addSubview:chkCase];

    // ── Regex Section ──

    NSBox* regexBox = [[NSBox alloc] initWithFrame:NSMakeRect(pad, 70, 450, 160)];
    regexBox.title = @"Ignore Regex";
    regexBox.titlePosition = NSAtTop;
    [cv addSubview:regexBox];
    NSView* regexContent = regexBox.contentView;

    NSButton* chkRegex = [NSButton checkboxWithTitle:@"Enable regex ignore" target:nil action:nil];
    chkRegex.frame = NSMakeRect(8, 110, 200, 18);
    chkRegex.state = Settings.IgnoreRegex ? NSControlStateValueOn : NSControlStateValueOff;
    [regexContent addSubview:chkRegex];

    NSButton* chkInvert = [NSButton checkboxWithTitle:@"Invert regex" target:nil action:nil];
    chkInvert.frame = NSMakeRect(220, 110, 200, 18);
    chkInvert.state = Settings.InvertRegex ? NSControlStateValueOn : NSControlStateValueOff;
    [regexContent addSubview:chkInvert];

    NSButton* chkInclNomatch = [NSButton checkboxWithTitle:@"Include non-match lines" target:nil action:nil];
    chkInclNomatch.frame = NSMakeRect(8, 86, 200, 18);
    chkInclNomatch.state = Settings.InclRegexNomatchLines ? NSControlStateValueOn : NSControlStateValueOff;
    [regexContent addSubview:chkInclNomatch];

    NSButton* chkHighlightReg = [NSButton checkboxWithTitle:@"Highlight regex ignores" target:nil action:nil];
    chkHighlightReg.frame = NSMakeRect(220, 86, 200, 18);
    chkHighlightReg.state = Settings.HighlightRegexIgnores ? NSControlStateValueOn : NSControlStateValueOff;
    [regexContent addSubview:chkHighlightReg];

    NSTextField* lblRegex = [NSTextField labelWithString:@"Regex:"];
    lblRegex.frame = NSMakeRect(8, 56, 50, 16);
    [regexContent addSubview:lblRegex];

    // Regex combo (NSComboBox with history)
    NSComboBox* comboRegex = [[NSComboBox alloc] initWithFrame:NSMakeRect(60, 52, 370, 24)];
    comboRegex.usesDataSource = NO;
    comboRegex.numberOfVisibleItems = 5;
    comboRegex.stringValue = [NSString stringWithUTF8String:Settings.IgnoreRegexStr[0].c_str()];

    for (int i = 0; i < UserSettings::cMaxRegexHistory && !Settings.IgnoreRegexStr[i].empty(); ++i)
    {
        [comboRegex addItemWithObjectValue:
            [NSString stringWithUTF8String:Settings.IgnoreRegexStr[i].c_str()]];
    }
    [regexContent addSubview:comboRegex];

    // ── OK / Cancel ──

    NSButton* btnOK = [[NSButton alloc] initWithFrame:NSMakeRect(300, 30, 80, 28)];
    btnOK.title = @"OK";
    btnOK.bezelStyle = NSBezelStyleRounded;
    btnOK.keyEquivalent = @"\r";
    btnOK.target = NSApp;
    btnOK.action = @selector(stopModal);
    [cv addSubview:btnOK];

    NSButton* btnCancel = [[NSButton alloc] initWithFrame:NSMakeRect(388, 30, 80, 28)];
    btnCancel.title = @"Cancel";
    btnCancel.bezelStyle = NSBezelStyleRounded;
    btnCancel.keyEquivalent = @"\033";
    btnCancel.target = NSApp;
    btnCancel.action = @selector(abortModal);
    [cv addSubview:btnCancel];

    NSModalResponse resp = [NSApp runModalForWindow:panel];
    [panel orderOut:nil];

    if (resp == NSModalResponseStop)
    {
        Settings.DetectMoves          = (chkMoves.state == NSControlStateValueOn);
        Settings.DetectSubBlockDiffs  = (chkSubBlock.state == NSControlStateValueOn);
        Settings.DetectSubLineMoves   = (chkSubLine.state == NSControlStateValueOn);
        Settings.DetectCharDiffs      = (chkCharDiffs.state == NSControlStateValueOn);

        Settings.IgnoreEmptyLines     = (chkEmpty.state == NSControlStateValueOn);
        Settings.IgnoreFoldedLines    = (chkFolded.state == NSControlStateValueOn);
        Settings.IgnoreHiddenLines    = (chkHidden.state == NSControlStateValueOn);
        Settings.IgnoreChangedSpaces  = (chkChgSpaces.state == NSControlStateValueOn);
        Settings.IgnoreAllSpaces      = (chkAllSpaces.state == NSControlStateValueOn);
        Settings.IgnoreEOL            = (chkEOL.state == NSControlStateValueOn);
        Settings.IgnoreCase           = (chkCase.state == NSControlStateValueOn);

        Settings.IgnoreRegex          = (chkRegex.state == NSControlStateValueOn);
        Settings.InvertRegex          = (chkInvert.state == NSControlStateValueOn);
        Settings.InclRegexNomatchLines= (chkInclNomatch.state == NSControlStateValueOn);
        Settings.HighlightRegexIgnores= (chkHighlightReg.state == NSControlStateValueOn);

        // Update regex history
        NSString* newRegex = comboRegex.stringValue;
        if (newRegex && newRegex.length > 0)
        {
            std::string regexStr = newRegex.UTF8String ?: "";
            if (!regexStr.empty())
                Settings.moveRegexToHistory(std::move(regexStr));
        }

        Settings.markAsDirty();
        Settings.save();

        // If in compare mode, trigger recompare
        if (compareMode && autoRecompareEnabled)
            recompareNeeded = true;
    }

    } // @autoreleasepool
}


// =====================================================================
//  Diffs Visual Filters Dialog
// =====================================================================

static void showDiffsVisualFiltersDialog()
{
    @autoreleasepool {

    NSPanel* panel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, 300, 230)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    panel.title = @"Diffs Visual Filters";
    [panel center];

    NSView* cv = panel.contentView;
    CGFloat lineH = 24;
    CGFloat y = 190;

    NSButton* chkHideMatches = [NSButton checkboxWithTitle:@"Hide matches" target:nil action:nil];
    chkHideMatches.frame = NSMakeRect(15, y, 260, 18);
    chkHideMatches.state = Settings.HideMatches ? NSControlStateValueOn : NSControlStateValueOff;
    [cv addSubview:chkHideMatches];
    y -= lineH;

    NSButton* chkHideNew = [NSButton checkboxWithTitle:@"Hide added/removed lines" target:nil action:nil];
    chkHideNew.frame = NSMakeRect(15, y, 260, 18);
    chkHideNew.state = Settings.HideNewLines ? NSControlStateValueOn : NSControlStateValueOff;
    [cv addSubview:chkHideNew];
    y -= lineH;

    NSButton* chkHideChanged = [NSButton checkboxWithTitle:@"Hide changed lines" target:nil action:nil];
    chkHideChanged.frame = NSMakeRect(15, y, 260, 18);
    chkHideChanged.state = Settings.HideChangedLines ? NSControlStateValueOn : NSControlStateValueOff;
    [cv addSubview:chkHideChanged];
    y -= lineH;

    NSButton* chkHideMoved = [NSButton checkboxWithTitle:@"Hide moved lines" target:nil action:nil];
    chkHideMoved.frame = NSMakeRect(15, y, 260, 18);
    chkHideMoved.state = Settings.HideMovedLines ? NSControlStateValueOn : NSControlStateValueOff;
    [cv addSubview:chkHideMoved];
    y -= lineH + 8;

    NSButton* chkShowOnlySel = [NSButton checkboxWithTitle:@"Show only selections" target:nil action:nil];
    chkShowOnlySel.frame = NSMakeRect(15, y, 260, 18);
    chkShowOnlySel.state = Settings.ShowOnlySelections ? NSControlStateValueOn : NSControlStateValueOff;
    [cv addSubview:chkShowOnlySel];

    // ── OK / Cancel ──

    NSButton* btnOK = [[NSButton alloc] initWithFrame:NSMakeRect(120, 15, 75, 28)];
    btnOK.title = @"OK";
    btnOK.bezelStyle = NSBezelStyleRounded;
    btnOK.keyEquivalent = @"\r";
    btnOK.target = NSApp;
    btnOK.action = @selector(stopModal);
    [cv addSubview:btnOK];

    NSButton* btnCancel = [[NSButton alloc] initWithFrame:NSMakeRect(205, 15, 75, 28)];
    btnCancel.title = @"Cancel";
    btnCancel.bezelStyle = NSBezelStyleRounded;
    btnCancel.keyEquivalent = @"\033";
    btnCancel.target = NSApp;
    btnCancel.action = @selector(abortModal);
    [cv addSubview:btnCancel];

    NSModalResponse resp = [NSApp runModalForWindow:panel];
    [panel orderOut:nil];

    if (resp == NSModalResponseStop)
    {
        Settings.HideMatches       = (chkHideMatches.state == NSControlStateValueOn);
        Settings.HideNewLines      = (chkHideNew.state == NSControlStateValueOn);
        Settings.HideChangedLines  = (chkHideChanged.state == NSControlStateValueOn);
        Settings.HideMovedLines    = (chkHideMoved.state == NSControlStateValueOn);
        Settings.ShowOnlySelections= (chkShowOnlySel.state == NSControlStateValueOn);

        Settings.markAsDirty();
        Settings.save();

        // If compare is active, re-apply visual filters
        if (compareMode)
        {
            // Unhide all first
            unhideAllLines(MAIN_VIEW);
            unhideAllLines(SUB_VIEW);

            // Re-apply filters
            if (Settings.HideMatches)
            {
                hideLines(MAIN_VIEW, 0, true);
                hideLines(SUB_VIEW, 0, true);
            }
            if (Settings.HideNewLines)
            {
                hideLines(MAIN_VIEW, MARKER_MASK_NEW_LINE, false);
                hideLines(SUB_VIEW, MARKER_MASK_NEW_LINE, false);
            }
            if (Settings.HideChangedLines)
            {
                hideLines(MAIN_VIEW, MARKER_MASK_CHANGED_LINE, false);
                hideLines(SUB_VIEW, MARKER_MASK_CHANGED_LINE, false);
            }
            if (Settings.HideMovedLines)
            {
                hideLines(MAIN_VIEW, MARKER_MASK_MOVED_LINE, false);
                hideLines(SUB_VIEW, MARKER_MASK_MOVED_LINE, false);
            }
        }
    }

    } // @autoreleasepool
}


// =====================================================================
//  About Dialog
// =====================================================================

static void showAboutDialog()
{
    @autoreleasepool {

    NSAlert* about = [[NSAlert alloc] init];
    about.messageText = @"ComparePlus (macOS)";
    about.informativeText = [NSString stringWithFormat:
        @"Version %s\n\n"
        @"A file comparison plugin for Notepad++ macOS.\n\n"
        @"Based on ComparePlus by Pavel Nedev\n"
        @"Original authors: Pavel Nedev, Jean-Sebastien Leroy,\n"
        @"Ty Landercasper, Jean-Francois Roux\n\n"
        @"macOS port for Notepad++ macOS by Andrey Letov\n\n"
        @"Licensed under the GNU GPL v3",
        PLUGIN_VERSION];
    [about runModal];

    } // @autoreleasepool
}


// =====================================================================
//  Notification handling
// =====================================================================

static void handleReady()
{
    pluginReady = true;

    // macOS: opt out of SCN_UPDATEUI and SCN_PAINTED forwarding.
    //
    // On Windows, ComparePlus drives scroll sync between compared panes
    // via its own handleUpdateUI → syncScrollPositions path. On macOS,
    // the host has a 60Hz timer-based scroll sync that we engage via
    // enableSyncScrolling: during compare mode (see doCompare), and the
    // plugin's Windows-style sync would fight that timer — causing the
    // secondary pane to snap back whenever the user tries to scroll it.
    //
    // By opting out of SCN_UPDATEUI here, our handleUpdateUI stops firing
    // and the host's timer becomes the sole scroll-sync mechanism.
    // SCN_MODIFIED (for auto-recompare) is NOT affected — it's a separate
    // subscription bit and stays on.
    //
    // Older hosts that don't recognize NPPM_SETPLUGINSUBSCRIPTIONS return
    // 0 from sendMessage. That's fine — on those hosts SCN_UPDATEUI was
    // never forwarded to plugins in the first place, so our handler was
    // already dead.
    nppData._sendMessage(nppData._nppHandle,
                         NPPM_SETPLUGINSUBSCRIPTIONS,
                         0,                          // wParam: empty mask
                         (intptr_t)PLUGIN_NAME);     // lParam: module name

    // Load settings
    Settings.load();

    // Set up initial state from settings
    autoRecompareEnabled = Settings.RecompareOnChange;
    bookmarksAsSyncPoints = Settings.BookmarksAsSync;
    navBarVisible = Settings.ShowNavBar;

    // Select color scheme
    if (isDarkModeNPP())
        Settings.useDarkColors();
    else
        Settings.useLightColors();

    // Set up markers
    setupMarkers();

    // Update menu checkmarks
    updateMenuChecks();
}


static void registerToolbarIcon(int funcIdx, const char *iconFile)
{
    nppData._sendMessage(nppData._nppHandle,
                         NPPM_ADDTOOLBARICON_FORDARKMODE,
                         (uintptr_t)funcItem[funcIdx]._cmdID,
                         (intptr_t)iconFile);
}

static void handleToolbarModification()
{
    // Register toolbar icons — filenames are relative to the plugin directory.
    // The host looks in ~/.notepad++/plugins/ComparePlus/{iconFile}
    if (Settings.EnableToolbar) {
        if (Settings.CompareTB)       registerToolbarIcon(1,  "Compare.png");         // Compare
        if (Settings.CompareSelTB)    registerToolbarIcon(2,  "CompareLines.png");    // Compare Selections
        if (Settings.ClearCompareTB)  registerToolbarIcon(11, "ClearCompare.png");    // Clear Active
        if (Settings.NavigationTB) {
            registerToolbarIcon(14, "Previous.png");   // Previous Diff
            registerToolbarIcon(15, "Next.png");       // Next Diff
            registerToolbarIcon(16, "First.png");      // First Diff
            registerToolbarIcon(17, "Last.png");       // Last Diff
        }
        if (Settings.DiffsFilterTB)   registerToolbarIcon(29, "DiffsFilters.png");   // Visual Filters
    }
}


static void handleShutdown()
{
    Settings.save();
    pluginReady = false;
}


static void handleBufferActivated(intptr_t buffId)
{
    if (!pluginReady)
        return;

    // If we are in compare mode, check if the activated buffer is part of the compare
    if (compareMode)
    {
        // Sync scroll when switching between paired buffers
        if (buffId == compareBuffIds[MAIN_VIEW] || buffId == compareBuffIds[SUB_VIEW])
        {
            int view = getCurrentViewId();
            syncScrollPositions(view);
        }
    }
}


static void handleFileBeforeClose(intptr_t buffId)
{
    if (!compareMode)
        return;

    // If one of the compared files is closing, clear the compare
    if (buffId == compareBuffIds[MAIN_VIEW] || buffId == compareBuffIds[SUB_VIEW])
    {
        clearAllCompares();
    }
}


static void handleFileSaved(intptr_t buffId)
{
    if (!compareMode || !autoRecompareEnabled)
        return;

    // If the saved file is part of the active compare, trigger recompare
    if (buffId == compareBuffIds[MAIN_VIEW] || buffId == compareBuffIds[SUB_VIEW])
    {
        recompareNeeded = true;
    }
}


static void handleUpdateUI(NppHandle viewHandle)
{
    if (!compareMode || !scrollSyncEnabled)
        return;

    int view = getViewIdSafe(viewHandle);
    if (view < 0)
        return;

    syncScrollPositions(view);
}


static void handleModified(NppHandle viewHandle)
{
    if (!compareMode || !autoRecompareEnabled)
        return;

    int view = getViewIdSafe(viewHandle);
    if (view < 0)
        return;

    // Defer recompare to avoid doing it on every keystroke
    recompareNeeded = true;
}


static void handleDarkModeChanged()
{
    if (isDarkModeNPP())
        Settings.useDarkColors();
    else
        Settings.useLightColors();

    applyMarkerColors();

    if (compareMode)
        setStyles(Settings);
}


// =====================================================================
//  Auto-recompare timer (invoked periodically via dispatch)
// =====================================================================

static void scheduleRecompareCheck()
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        if (recompareNeeded && compareMode && autoRecompareEnabled && pluginReady)
        {
            recompareNeeded = false;

            // Save which buffers we had
            intptr_t savedBuffs[2] = { compareBuffIds[0], compareBuffIds[1] };

            // Run new compare
            clearAllCompares();

            // Re-activate the buffers
            if (savedBuffs[0] >= 0)
                activateBufferID(savedBuffs[0]);
            if (savedBuffs[1] >= 0)
                activateBufferID(savedBuffs[1]);

            doCompare(false, false);
        }

        // Re-schedule
        if (pluginReady)
            scheduleRecompareCheck();
    });
}


// =====================================================================
//  Required plugin exports
// =====================================================================

extern "C" NPP_EXPORT void setInfo(NppData data)
{
    nppData = data;

    // Build the FuncItem array
    int idx = 0;

    // Helper macro for menu items
    #define MAKE_ITEM(name, func, shortcut, check) do { \
        strlcpy(funcItem[idx]._itemName, name, NPP_MENU_ITEM_SIZE); \
        funcItem[idx]._pFunc = func; \
        funcItem[idx]._pShKey = shortcut; \
        funcItem[idx]._init2Check = check; \
        idx++; \
    } while(0)

    #define MAKE_SEPARATOR() do { \
        strlcpy(funcItem[idx]._itemName, "-", NPP_MENU_ITEM_SIZE); \
        funcItem[idx]._pFunc = nullptr; \
        funcItem[idx]._pShKey = nullptr; \
        funcItem[idx]._init2Check = false; \
        idx++; \
    } while(0)

    // 0: (placeholder — keeps toolbar button indices stable)
    MAKE_SEPARATOR();
    // 1: Compare
    MAKE_ITEM("Compare", cmdCompare, &skCompare, false);
    // 2: Compare Selections
    MAKE_ITEM("Compare Selections", cmdCompareSelections, &skCompareSel, false);
    // --- Hidden for now (uncomment to re-enable) ---
    // 3: Find Unique Lines
    MAKE_SEPARATOR(); // was: MAKE_ITEM("Find Unique Lines", cmdFindUniqueLines, &skFindUnique, false);
    // 4: Find Unique Lines in Selections
    MAKE_SEPARATOR(); // was: MAKE_ITEM("Find Unique Lines in Selections", cmdFindUniqueLinesInSel, &skFindUniqueSel, false);
    // 5: separator
    MAKE_SEPARATOR();
    // 6: Diff since last Save
    MAKE_SEPARATOR(); // was: MAKE_ITEM("Diff since last Save", cmdDiffSinceLastSave, &skDiffSinceSave, false);
    // 7: Compare to Clipboard
    MAKE_SEPARATOR(); // was: MAKE_ITEM("Compare file/selection to Clipboard", cmdCompareToClipboard, &skCompareClip, false);
    // 8: SVN Diff
    MAKE_SEPARATOR(); // was: MAKE_ITEM("SVN Diff", cmdSVNDiff, &skSVNDiff, false);
    // 9: Git Diff
    MAKE_SEPARATOR(); // was: MAKE_ITEM("Git Diff", cmdGitDiff, &skGitDiff, false);
    // 10: separator
    MAKE_SEPARATOR();
    // --- End hidden ---
    // 11: Clear Active Compare
    MAKE_ITEM("Clear Active Compare", cmdClearActiveCompare, &skClearActive, false);
    // 12: Clear All Compares
    MAKE_ITEM("Clear All Compares", cmdClearAllCompares, nullptr, false);
    // 13: separator
    MAKE_SEPARATOR();
    // 14: Previous Diff Block
    MAKE_ITEM("Previous Diff Block", cmdPrevDiffBlock, &skPrevDiff, false);
    // 15: Next Diff Block
    MAKE_ITEM("Next Diff Block", cmdNextDiffBlock, &skNextDiff, false);
    // 16: First Diff Block
    MAKE_ITEM("First Diff Block", cmdFirstDiffBlock, &skFirstDiff, false);
    // 17: Last Diff Block
    MAKE_ITEM("Last Diff Block", cmdLastDiffBlock, &skLastDiff, false);
    // 18: Previous Diff in Changed Line
    MAKE_ITEM("Previous Diff in Changed Line", cmdPrevDiffInChangedLine, &skPrevChangedLine, false);
    // 19: Next Diff in Changed Line
    MAKE_ITEM("Next Diff in Changed Line", cmdNextDiffInChangedLine, &skNextChangedLine, false);
    // 20: separator
    MAKE_SEPARATOR();
    // 21: Active Compare Summary
    MAKE_ITEM("Active Compare Summary", cmdActiveCompareSummary, nullptr, false);
    // 22: separator
    MAKE_SEPARATOR();
    // 23: Copy all/selected visible lines
    MAKE_ITEM("Copy Visible Lines", cmdCopyVisibleLines, nullptr, false);
    // 24: Delete all/selected visible lines
    MAKE_ITEM("Delete Visible Lines", cmdDeleteVisibleLines, nullptr, false);
    // 25: Bookmark all/selected visible lines
    MAKE_ITEM("Bookmark Visible Lines", cmdBookmarkVisibleLines, nullptr, false);
    // 26: separator
    MAKE_SEPARATOR();
    // 27: Compare Options
    MAKE_ITEM("Compare Options...", cmdCompareOptions, nullptr, false);
    // 28: Use Bookmarks as Manual Sync Points
    MAKE_ITEM("Use Bookmarks as Manual Sync Points", cmdBookmarksAsSyncPoints, nullptr, false);
    // 29: Diffs Visual Filters
    MAKE_ITEM("Diffs Visual Filters...", cmdDiffsVisualFilters, nullptr, false);
    // 30: separator
    MAKE_SEPARATOR();
    // 31: Navigation Bar (hidden for now — uncomment to re-enable)
    MAKE_SEPARATOR(); // was: MAKE_ITEM("Navigation Bar", cmdNavigationBar, nullptr, false);
    // 32: Auto Re-Compare on Change (hidden for now — uncomment to re-enable)
    MAKE_SEPARATOR(); // was: MAKE_ITEM("Auto Re-Compare on Change", cmdAutoRecompare, nullptr, false);
    // 33: separator
    MAKE_SEPARATOR();
    // 34: Settings
    MAKE_ITEM("Settings...", cmdSettings, nullptr, false);
    // 35: separator
    MAKE_SEPARATOR();
    // 36: Help / About
    MAKE_ITEM("Help / About...", cmdHelpAbout, nullptr, false);

    #undef MAKE_ITEM
    #undef MAKE_SEPARATOR

    assert(idx == NB_MENU_COMMANDS);
}


extern "C" NPP_EXPORT const char* getName()
{
    return PLUGIN_NAME;
}


extern "C" NPP_EXPORT FuncItem* getFuncsArray(int* nbF)
{
    *nbF = NB_MENU_COMMANDS;
    return funcItem;
}


extern "C" NPP_EXPORT void beNotified(SCNotification* notifyCode)
{
    if (!notifyCode)
        return;

    unsigned int code = notifyCode->nmhdr.code;
    NppHandle hwndFrom = (NppHandle)(uintptr_t)notifyCode->nmhdr.hwndFrom;

    switch (code)
    {
        case NPPN_READY:
            handleReady();
            // Start the recompare check timer
            scheduleRecompareCheck();
            break;

        case NPPN_TBMODIFICATION:
            handleToolbarModification();
            break;

        case NPPN_SHUTDOWN:
            handleShutdown();
            break;

        case NPPN_BUFFERACTIVATED:
        {
            intptr_t buffId = (intptr_t)notifyCode->nmhdr.idFrom;
            handleBufferActivated(buffId);
            break;
        }

        case NPPN_FILEBEFORECLOSE:
        {
            intptr_t buffId = (intptr_t)notifyCode->nmhdr.idFrom;
            handleFileBeforeClose(buffId);
            break;
        }

        case NPPN_FILESAVED:
        {
            intptr_t buffId = (intptr_t)notifyCode->nmhdr.idFrom;
            handleFileSaved(buffId);
            break;
        }

        case NPPN_DARKMODECHANGED:
            handleDarkModeChanged();
            break;

        case SCN_UPDATEUI:
            handleUpdateUI(hwndFrom);
            break;

        case SCN_MODIFIED:
            handleModified(hwndFrom);
            break;

        default:
            break;
    }
}


extern "C" NPP_EXPORT intptr_t messageProc(uint32_t msg, uintptr_t wParam, intptr_t lParam)
{
    // Handle inter-plugin messages if needed
    return 1;
}


// ViewLocation::save / ViewLocation::restore are in CompareHelpers.mm
// (removed from here to avoid duplicate symbols)
#if 0 // DISABLED — defined in CompareHelpers.mm====

void ViewLocation::save(int view, intptr_t firstLine)
{
    _view = view;

    intptr_t curLine = getCurrentLine(view);
    _firstLine = (firstLine >= 0) ? firstLine : curLine;

    _visibleLineOffset = getVisibleFromDocLine(view, curLine) - getFirstVisibleLine(view);
}


bool ViewLocation::restore(bool ensureCaretVisible) const
{
    if (_view < 0 || _firstLine < 0)
        return false;

    intptr_t line = _firstLine;
    if (line >= getLinesCount(_view))
        line = getLinesCount(_view) - 1;

    CallScintilla(_view, SCI_GOTOLINE, line, 0);

    intptr_t visLine = getVisibleFromDocLine(_view, line);
    intptr_t targetFirstVisible = visLine - _visibleLineOffset;
    if (targetFirstVisible < 0)
        targetFirstVisible = 0;

    CallScintilla(_view, SCI_SETFIRSTVISIBLELINE, targetFirstVisible, 0);

    if (ensureCaretVisible)
        CallScintilla(_view, SCI_SCROLLCARET, 0, 0);

    return true;
}
#endif
