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

#pragma once

#include <cstdint>
#include <cassert>
#include <vector>
#include <string>
#include <utility>

#include "NppPluginInterfaceMac.h"
#include "Scintilla.h"

struct UserSettings;  // forward declaration


// =====================================================================
//  View constants
// =====================================================================

// MAIN_VIEW and SUB_VIEW are already defined in NppPluginInterfaceMac.h
// as 0 and 1 respectively.


// =====================================================================
//  Marker enumerations and masks
// =====================================================================

enum Marker_t
{
    MARKER_CHANGED_LINE = 0,
    MARKER_ADDED_LINE,
    MARKER_REMOVED_LINE,
    MARKER_MOVED_LINE,
    MARKER_BLANK,
    MARKER_CHANGED_SYMBOL,
    MARKER_CHANGED_LOCAL_SYMBOL,
    MARKER_ADDED_SYMBOL,
    MARKER_ADDED_LOCAL_SYMBOL,
    MARKER_REMOVED_SYMBOL,
    MARKER_REMOVED_LOCAL_SYMBOL,
    MARKER_MOVED_LINE_SYMBOL,
    MARKER_MOVED_BLOCK_BEGIN_SYMBOL,
    MARKER_MOVED_BLOCK_MID_SYMBOL,
    MARKER_MOVED_BLOCK_END_SYMBOL,
    MARKER_ARROW_SYMBOL
};


constexpr int MARKER_MASK_CHANGED       = (1 << MARKER_CHANGED_LINE)   | (1 << MARKER_CHANGED_SYMBOL);
constexpr int MARKER_MASK_CHANGED_LOCAL = (1 << MARKER_CHANGED_LINE)   | (1 << MARKER_CHANGED_LOCAL_SYMBOL);
constexpr int MARKER_MASK_ADDED         = (1 << MARKER_ADDED_LINE)     | (1 << MARKER_ADDED_SYMBOL);
constexpr int MARKER_MASK_ADDED_LOCAL   = (1 << MARKER_ADDED_LINE)     | (1 << MARKER_ADDED_LOCAL_SYMBOL);
constexpr int MARKER_MASK_REMOVED       = (1 << MARKER_REMOVED_LINE)   | (1 << MARKER_REMOVED_SYMBOL);
constexpr int MARKER_MASK_REMOVED_LOCAL = (1 << MARKER_REMOVED_LINE)   | (1 << MARKER_REMOVED_LOCAL_SYMBOL);
constexpr int MARKER_MASK_MOVED_SINGLE  = (1 << MARKER_MOVED_LINE)     | (1 << MARKER_MOVED_LINE_SYMBOL);
constexpr int MARKER_MASK_MOVED_BEGIN   = (1 << MARKER_MOVED_LINE)     | (1 << MARKER_MOVED_BLOCK_BEGIN_SYMBOL);
constexpr int MARKER_MASK_MOVED_MID     = (1 << MARKER_MOVED_LINE)     | (1 << MARKER_MOVED_BLOCK_MID_SYMBOL);
constexpr int MARKER_MASK_MOVED_END     = (1 << MARKER_MOVED_LINE)     | (1 << MARKER_MOVED_BLOCK_END_SYMBOL);
constexpr int MARKER_MASK_MOVED         = (1 << MARKER_MOVED_LINE)     | (1 << MARKER_MOVED_LINE_SYMBOL) |
                                          (1 << MARKER_MOVED_BLOCK_BEGIN_SYMBOL) |
                                          (1 << MARKER_MOVED_BLOCK_MID_SYMBOL) |
                                          (1 << MARKER_MOVED_BLOCK_END_SYMBOL);

constexpr int MARKER_MASK_BLANK         = (1 << MARKER_BLANK);
constexpr int MARKER_MASK_ARROW         = (1 << MARKER_ARROW_SYMBOL);

constexpr int MARKER_MASK_NEW_LINE      = (1 << MARKER_ADDED_LINE) | (1 << MARKER_REMOVED_LINE);
constexpr int MARKER_MASK_CHANGED_LINE  = (1 << MARKER_CHANGED_LINE);
constexpr int MARKER_MASK_MOVED_LINE    = (1 << MARKER_MOVED_LINE);
constexpr int MARKER_MASK_DIFF_LINE     = MARKER_MASK_NEW_LINE | MARKER_MASK_CHANGED_LINE;
constexpr int MARKER_MASK_LINE          = MARKER_MASK_DIFF_LINE | MARKER_MASK_MOVED_LINE;

constexpr int MARKER_MASK_SYMBOL        = (1 << MARKER_CHANGED_SYMBOL) |
                                          (1 << MARKER_CHANGED_LOCAL_SYMBOL) |
                                          (1 << MARKER_ADDED_SYMBOL) |
                                          (1 << MARKER_ADDED_LOCAL_SYMBOL) |
                                          (1 << MARKER_REMOVED_SYMBOL) |
                                          (1 << MARKER_REMOVED_LOCAL_SYMBOL) |
                                          (1 << MARKER_MOVED_LINE_SYMBOL) |
                                          (1 << MARKER_MOVED_BLOCK_BEGIN_SYMBOL) |
                                          (1 << MARKER_MOVED_BLOCK_MID_SYMBOL) |
                                          (1 << MARKER_MOVED_BLOCK_END_SYMBOL);

constexpr int MARKER_MASK_ALL           = MARKER_MASK_LINE | MARKER_MASK_SYMBOL;


// =====================================================================
//  Plugin globals (defined in the main plugin .mm file)
// =====================================================================

extern NppData nppData;

extern int nppBookmarkMarker;
extern int indicatorHighlight;
extern int marginNum;
extern int gMarginWidth;


// =====================================================================
//  CallScintilla  --  the critical bridge used by the diff engine
//  Routes SCI_* messages through the macOS plugin API.
// =====================================================================

// Defined in EngineBridge.mm (not inline — must be a real symbol for Engine.cpp linkage)
intptr_t CallScintilla(int viewNum, unsigned int uMsg, uintptr_t wParam, intptr_t lParam);


// =====================================================================
//  RAII helpers
// =====================================================================

/// Temporarily clears the read-only flag for a Scintilla view.
struct ScopedViewWriteEnabler
{
    ScopedViewWriteEnabler(int view) : _view(view)
    {
        _isRO = static_cast<bool>(CallScintilla(_view, SCI_GETREADONLY, 0, 0));
        if (_isRO)
            CallScintilla(_view, SCI_SETREADONLY, false, 0);
    }

    ~ScopedViewWriteEnabler()
    {
        if (_isRO)
            CallScintilla(_view, SCI_SETREADONLY, true, 0);
    }

private:
    int  _view;
    bool _isRO;
};


/// Temporarily blocks undo collection for a Scintilla view.
struct ScopedViewUndoCollectionBlocker
{
    ScopedViewUndoCollectionBlocker(int view) : _view(view)
    {
        _isUndoOn = static_cast<bool>(CallScintilla(_view, SCI_GETUNDOCOLLECTION, 0, 0));
        if (_isUndoOn)
        {
            CallScintilla(_view, SCI_SETUNDOCOLLECTION, false, 0);
            CallScintilla(_view, SCI_EMPTYUNDOBUFFER, 0, 0);
        }
    }

    ~ScopedViewUndoCollectionBlocker()
    {
        if (_isUndoOn)
            CallScintilla(_view, SCI_SETUNDOCOLLECTION, true, 0);
    }

private:
    int  _view;
    bool _isUndoOn;
};


/// Wraps an undo action for a Scintilla view.
struct ScopedViewUndoAction
{
    ScopedViewUndoAction(int view) : _view(view)
    {
        CallScintilla(_view, SCI_BEGINUNDOACTION, 0, 0);
    }

    ~ScopedViewUndoAction()
    {
        CallScintilla(_view, SCI_ENDUNDOACTION, 0, 0);
    }

private:
    int _view;
};


/// Saves and restores the first visible line of a view.
struct ScopedFirstVisibleLineStore
{
    ScopedFirstVisibleLineStore(int view) : _view(view)
    {
        _firstVisibleLine = CallScintilla(view, SCI_GETFIRSTVISIBLELINE, 0, 0);
    }

    ~ScopedFirstVisibleLineStore()
    {
        if (_firstVisibleLine >= 0)
            CallScintilla(_view, SCI_SETFIRSTVISIBLELINE, _firstVisibleLine, 0);
    }

    void set(intptr_t newFirstVisible)
    {
        _firstVisibleLine = newFirstVisible;
    }

private:
    int      _view;
    intptr_t _firstVisibleLine;
};


// =====================================================================
//  ViewLocation — saves/restores a view's scroll position
// =====================================================================

struct ViewLocation
{
    ViewLocation() = default;

    ViewLocation(int view, intptr_t firstLine)
    {
        save(view, firstLine);
    }

    ViewLocation(int view)
    {
        save(view);
    }

    void save(int view, intptr_t firstLine = -1);
    bool restore(bool ensureCaretVisible = false) const;

    int getView() const { return _view; }

private:
    int      _view              {-1};
    intptr_t _firstLine         {-1};
    intptr_t _visibleLineOffset {0};
};


// =====================================================================
//  Inline Scintilla query helpers
// =====================================================================

inline bool isFileEmpty(int view)
{
    return (CallScintilla(view, SCI_GETLENGTH, 0, 0) == 0);
}


inline int getCurrentViewId()
{
    int which = -1;
    nppData._sendMessage(nppData._nppHandle, NPPM_GETCURRENTSCINTILLA, 0, (intptr_t)&which);
    return (which <= 0) ? MAIN_VIEW : SUB_VIEW;
}


inline NppHandle getView(int viewId)
{
    return (viewId == MAIN_VIEW) ? nppData._scintillaMainHandle : nppData._scintillaSecondHandle;
}


inline int getViewId(NppHandle view)
{
    return (view == nppData._scintillaMainHandle) ? MAIN_VIEW : SUB_VIEW;
}


inline int getViewIdSafe(NppHandle view)
{
    return (view == nppData._scintillaMainHandle)  ? MAIN_VIEW :
           (view == nppData._scintillaSecondHandle) ? SUB_VIEW : -1;
}


inline int getOtherViewId()
{
    return (getCurrentViewId() == MAIN_VIEW) ? SUB_VIEW : MAIN_VIEW;
}


inline NppHandle getOtherView(int view)
{
    return (view == MAIN_VIEW) ? nppData._scintillaSecondHandle : nppData._scintillaMainHandle;
}


inline int getOtherViewId(int view)
{
    return (view == MAIN_VIEW) ? SUB_VIEW : MAIN_VIEW;
}


inline intptr_t getCurrentBuffId()
{
    return nppData._sendMessage(nppData._nppHandle, NPPM_GETCURRENTBUFFERID, 0, 0);
}


inline int viewIdFromBuffId(intptr_t buffId)
{
    intptr_t index = nppData._sendMessage(nppData._nppHandle, NPPM_GETPOSFROMBUFFERID, buffId, 0);
    return static_cast<int>(index >> 30);
}


inline int posFromBuffId(intptr_t buffId)
{
    intptr_t index = nppData._sendMessage(nppData._nppHandle, NPPM_GETPOSFROMBUFFERID, buffId, 0);
    return static_cast<int>(index & 0x3FFFFFFF);
}


inline int getEncoding(intptr_t buffId)
{
    return static_cast<int>(nppData._sendMessage(nppData._nppHandle, NPPM_GETBUFFERENCODING, buffId, 0));
}


inline int getCodepage(int view)
{
    return (int)CallScintilla(view, SCI_GETCODEPAGE, 0, 0);
}


inline intptr_t getDocId(int view)
{
    return CallScintilla(view, SCI_GETDOCPOINTER, 0, 0);
}


inline int getNumberOfFiles(int viewId)
{
    return static_cast<int>(nppData._sendMessage(nppData._nppHandle, NPPM_GETNBOPENFILES, 0,
            viewId == MAIN_VIEW ? PRIMARY_VIEW : SECOND_VIEW));
}


// =====================================================================
//  Line position helpers
// =====================================================================

inline intptr_t getLineStart(int view, intptr_t line)
{
    return CallScintilla(view, SCI_POSITIONFROMLINE, line, 0);
}


inline intptr_t getLineEnd(int view, intptr_t line)
{
    return CallScintilla(view, SCI_GETLINEENDPOSITION, line, 0);
}


inline intptr_t getLinesCount(int view)
{
    return CallScintilla(view, SCI_GETLINECOUNT, 0, 0);
}


inline intptr_t getEndLine(int view)
{
    return CallScintilla(view, SCI_GETLINECOUNT, 0, 0) - 1;
}


inline intptr_t getEndNotEmptyLine(int view)
{
    intptr_t line = CallScintilla(view, SCI_GETLINECOUNT, 0, 0) - 1;
    return ((getLineEnd(view, line) - getLineStart(view, line)) == 0) ? line - 1 : line;
}


inline intptr_t getVisibleFromDocLine(int view, intptr_t line)
{
    return CallScintilla(view, SCI_VISIBLEFROMDOCLINE, line, 0);
}


inline intptr_t getDocLineFromVisible(int view, intptr_t line)
{
    return CallScintilla(view, SCI_DOCLINEFROMVISIBLE, line, 0);
}


inline intptr_t getCurrentLine(int view)
{
    return CallScintilla(view, SCI_LINEFROMPOSITION, CallScintilla(view, SCI_GETCURRENTPOS, 0, 0), 0);
}


inline intptr_t getCurrentVisibleLine(int view)
{
    return getVisibleFromDocLine(view, getCurrentLine(view));
}


inline intptr_t getFirstVisibleLine(int view)
{
    return CallScintilla(view, SCI_GETFIRSTVISIBLELINE, 0, 0);
}


inline intptr_t getFirstLine(int view)
{
    return getDocLineFromVisible(view, getFirstVisibleLine(view));
}


inline intptr_t getLastVisibleLine(int view)
{
    return (getFirstVisibleLine(view) + CallScintilla(view, SCI_LINESONSCREEN, 0, 0) - 1);
}


inline intptr_t getLastLine(int view)
{
    return getDocLineFromVisible(view, getLastVisibleLine(view));
}


inline intptr_t getCenterVisibleLine(int view)
{
    return (getFirstVisibleLine(view) + (CallScintilla(view, SCI_LINESONSCREEN, 0, 0) / 2));
}


inline intptr_t getCenterLine(int view)
{
    return getDocLineFromVisible(view, getCenterVisibleLine(view));
}


inline intptr_t getUnhiddenLine(int view, intptr_t line)
{
    return getDocLineFromVisible(view, getVisibleFromDocLine(view, line));
}


inline intptr_t getPreviousUnhiddenLine(int view, intptr_t line)
{
    intptr_t visibleLine = getVisibleFromDocLine(view, line) - 1;
    if (visibleLine < 0) visibleLine = 0;
    return getDocLineFromVisible(view, visibleLine);
}


inline void gotoClosestUnhiddenLine(int view)
{
    CallScintilla(view, SCI_GOTOLINE, getUnhiddenLine(view, getCurrentLine(view)), 0);
}


inline void gotoClosestUnhiddenLine(int view, intptr_t line)
{
    CallScintilla(view, SCI_GOTOLINE, getUnhiddenLine(view, line), 0);
}


inline intptr_t getFirstVisibleLineOffset(int view, intptr_t line)
{
    return (getVisibleFromDocLine(view, line) - getFirstVisibleLine(view));
}


inline bool getNextLineAfterFold(int view, intptr_t* line)
{
    const intptr_t foldParent = CallScintilla(view, SCI_GETFOLDPARENT, *line, 0);

    if ((foldParent < 0) || (CallScintilla(view, SCI_GETFOLDEXPANDED, foldParent, 0) != 0))
        return false;

    *line = CallScintilla(view, SCI_GETLASTCHILD, foldParent, -1) + 1;
    return true;
}


inline intptr_t getWrapCount(int view, intptr_t line)
{
    return CallScintilla(view, SCI_WRAPCOUNT, line, 0);
}


inline intptr_t getLineAnnotation(int view, intptr_t line)
{
    return CallScintilla(view, SCI_ANNOTATIONGETLINES, line, 0);
}


// =====================================================================
//  Indicator helpers
// =====================================================================

inline intptr_t getIndicatorStartPos(int view, intptr_t pos)
{
    return CallScintilla(view, SCI_INDICATORSTART, indicatorHighlight, pos);
}


inline intptr_t getIndicatorEndPos(int view, intptr_t pos)
{
    return CallScintilla(view, SCI_INDICATOREND, indicatorHighlight, pos);
}


inline bool allocateIndicator()
{
    if (indicatorHighlight >= 0)
        return true;

    int result = (int)nppData._sendMessage(nppData._nppHandle, NPPM_ALLOCATEINDICATOR, 1,
                                           (intptr_t)&indicatorHighlight);

    // Set default indicator but avoid INDIC_CONTAINER + 1 (conflicts with other plugins)
    if (!result)
        indicatorHighlight = INDIC_CONTAINER + 7;

    return true;
}


inline bool allocateMarginNum()
{
    if (marginNum >= 0)
        return true;

    marginNum = (int)CallScintilla(MAIN_VIEW, SCI_GETMARGINS, 0, 0);

    if (marginNum < (int)CallScintilla(SUB_VIEW, SCI_GETMARGINS, 0, 0))
        marginNum = (int)CallScintilla(SUB_VIEW, SCI_GETMARGINS, 0, 0);

    CallScintilla(MAIN_VIEW, SCI_SETMARGINS, marginNum + 1, 0);
    CallScintilla(SUB_VIEW,  SCI_SETMARGINS, marginNum + 1, 0);

    return (marginNum >= 0);
}


// =====================================================================
//  Line state queries
// =====================================================================

inline bool isLineWrapped(int view, intptr_t line)
{
    return (CallScintilla(view, SCI_WRAPCOUNT, line, 0) > 1);
}


inline bool isLineAnnotated(int view, intptr_t line)
{
    return (getLineAnnotation(view, line) > 0);
}


inline bool isLineMarked(int view, intptr_t line, int markMask)
{
    return ((CallScintilla(view, SCI_MARKERGET, line, 0) & markMask) != 0);
}


inline bool isLineEmpty(int view, intptr_t line)
{
    return ((getLineEnd(view, line) - getLineStart(view, line)) == 0);
}


inline bool isLineHidden(int view, intptr_t line)
{
    return (CallScintilla(view, SCI_GETLINEVISIBLE, line, 0) == 0);
}


inline bool isLineFolded(int view, intptr_t line)
{
    const intptr_t foldParent = CallScintilla(view, SCI_GETFOLDPARENT, line, 0);
    return (foldParent >= 0 && CallScintilla(view, SCI_GETFOLDEXPANDED, foldParent, 0) == 0);
}


inline bool isLineFoldedFoldPoint(int view, intptr_t line)
{
    const intptr_t contractedFold = CallScintilla(view, SCI_CONTRACTEDFOLDNEXT, line, 0);
    return (contractedFold >= 0 && contractedFold == line);
}


inline bool isLineVisible(int view, intptr_t line)
{
    intptr_t lineStart = getVisibleFromDocLine(view, line);
    intptr_t lineEnd   = lineStart + getWrapCount(view, line) - 1;
    return (getFirstVisibleLine(view) <= lineEnd && getLastVisibleLine(view) >= lineStart);
}


// =====================================================================
//  Selection helpers
// =====================================================================

inline bool isSelection(int view)
{
    return (CallScintilla(view, SCI_GETSELECTIONEND, 0, 0) -
            CallScintilla(view, SCI_GETSELECTIONSTART, 0, 0) != 0);
}


inline bool isSelectionVertical(int view)
{
    return (CallScintilla(view, SCI_SELECTIONISRECTANGLE, 0, 0) != 0);
}


inline bool isMultiSelection(int view)
{
    return (CallScintilla(view, SCI_GETSELECTIONS, 0, 0) > 1);
}


inline std::pair<intptr_t, intptr_t> getSelection(int view)
{
    return std::make_pair(CallScintilla(view, SCI_GETSELECTIONSTART, 0, 0),
                          CallScintilla(view, SCI_GETSELECTIONEND, 0, 0));
}


inline void clearSelection(int view)
{
    const intptr_t currentPos = CallScintilla(view, SCI_GETCURRENTPOS, 0, 0);
    CallScintilla(view, SCI_SETEMPTYSELECTION, currentPos, 0);
}


inline void setSelection(int view, intptr_t start, intptr_t end, bool scrollView = false)
{
    if (scrollView)
    {
        CallScintilla(view, SCI_SETSEL, start, end);
    }
    else
    {
        CallScintilla(view, SCI_SETSELECTIONSTART, start, 0);
        CallScintilla(view, SCI_SETSELECTIONEND, end, 0);
    }
}


// =====================================================================
//  Bookmark helpers
// =====================================================================

inline void readNppBookmarkID()
{
    nppBookmarkMarker = 1 << static_cast<int>(
        nppData._sendMessage(nppData._nppHandle, NPPM_GETBOOKMARKID, 0, 0));
}


inline bool isLineBookmarked(int view, intptr_t line)
{
    return isLineMarked(view, line, nppBookmarkMarker);
}


inline intptr_t getNextBookmarkedLine(int view, intptr_t currentLine)
{
    return CallScintilla(view, SCI_MARKERNEXT, currentLine, nppBookmarkMarker);
}


inline void bookmarkLine(int view, intptr_t line)
{
    CallScintilla(view, SCI_MARKERADDSET, line, nppBookmarkMarker);
}


// =====================================================================
//  Annotation / editing helpers
// =====================================================================

inline void clearAnnotation(int view, intptr_t line)
{
    CallScintilla(view, SCI_ANNOTATIONSETTEXT, line, (intptr_t)NULL);
}


inline void deleteRange(int view, intptr_t startPos, intptr_t endPos)
{
    CallScintilla(view, SCI_SETTARGETRANGE, startPos, endPos);
    CallScintilla(view, SCI_REPLACETARGET, (uintptr_t)-1, (intptr_t)"");
}


inline void deleteLine(int view, intptr_t line)
{
    const intptr_t startPos = getLineStart(view, line);
    const intptr_t endPos   = startPos + CallScintilla(view, SCI_LINELENGTH, line, 0);
    deleteRange(view, startPos, endPos);
}


inline void clearMarks(int view, intptr_t line)
{
    CallScintilla(view, SCI_MARKERDELETE, line, MARKER_CHANGED_LINE);
    CallScintilla(view, SCI_MARKERDELETE, line, MARKER_ADDED_LINE);
    CallScintilla(view, SCI_MARKERDELETE, line, MARKER_REMOVED_LINE);
    CallScintilla(view, SCI_MARKERDELETE, line, MARKER_MOVED_LINE);
    CallScintilla(view, SCI_MARKERDELETE, line, MARKER_BLANK);
    CallScintilla(view, SCI_MARKERDELETE, line, MARKER_CHANGED_SYMBOL);
    CallScintilla(view, SCI_MARKERDELETE, line, MARKER_CHANGED_LOCAL_SYMBOL);
    CallScintilla(view, SCI_MARKERDELETE, line, MARKER_ADDED_SYMBOL);
    CallScintilla(view, SCI_MARKERDELETE, line, MARKER_ADDED_LOCAL_SYMBOL);
    CallScintilla(view, SCI_MARKERDELETE, line, MARKER_REMOVED_SYMBOL);
    CallScintilla(view, SCI_MARKERDELETE, line, MARKER_REMOVED_LOCAL_SYMBOL);
    CallScintilla(view, SCI_MARKERDELETE, line, MARKER_MOVED_LINE_SYMBOL);
    CallScintilla(view, SCI_MARKERDELETE, line, MARKER_MOVED_BLOCK_BEGIN_SYMBOL);
    CallScintilla(view, SCI_MARKERDELETE, line, MARKER_MOVED_BLOCK_MID_SYMBOL);
    CallScintilla(view, SCI_MARKERDELETE, line, MARKER_MOVED_BLOCK_END_SYMBOL);
}


inline void clearChangedIndicatorFull(int view)
{
    // forward-declared; implemented in CompareHelpers.mm
    void clearChangedIndicator(int view, intptr_t start, intptr_t length);
    clearChangedIndicator(view, 0, CallScintilla(view, SCI_GETLENGTH, 0, 0));
}


// =====================================================================
//  Dark mode helpers
// =====================================================================

inline bool isDarkModeNPP()
{
    return (bool)nppData._sendMessage(nppData._nppHandle, NPPM_ISDARKMODEENABLED, 0, 0);
}


// =====================================================================
//  Npp path / info helpers
// =====================================================================

inline std::string getPluginsConfigDir()
{
    char buf[1024] = {};
    nppData._sendMessage(nppData._nppHandle, NPPM_GETPLUGINSCONFIGDIR, 0, (intptr_t)buf);
    return std::string(buf);
}


inline std::string getPluginsHomePath()
{
    char buf[1024] = {};
    nppData._sendMessage(nppData._nppHandle, NPPM_GETPLUGINHOMEPATH, sizeof(buf) - 1, (intptr_t)buf);
    return std::string(buf);
}


inline int getNotepadVersion()
{
    return (int)nppData._sendMessage(nppData._nppHandle, NPPM_GETNPPVERSION, 1, 0);
}


// =====================================================================
//  Non-inline function declarations (implemented in CompareHelpers.mm)
// =====================================================================

std::vector<intptr_t> getVisibleLines(int view, bool skipFirstLine = false);
std::vector<intptr_t> getAllBookmarkedLines(int view);
void bookmarkMarkedLines(int view, int markMask);

intptr_t otherViewMatchingLine(int view, intptr_t line, intptr_t adjustment = 0, bool check = false);
void activateBufferID(intptr_t buffId);
std::pair<intptr_t, intptr_t> getSelectionLines(int view);

int showArrowSymbol(int view, intptr_t line, bool down);

void blinkLine(int view, intptr_t line);
void blinkRange(int view, intptr_t startPos, intptr_t endPos);

void centerAt(int view, intptr_t line);

void markTextAsChanged(int view, intptr_t start, intptr_t length, int color);
void clearChangedIndicator(int view, intptr_t start, intptr_t length);

void setNormalView(int view);
void setCompareView(int view, bool showMargin, int blankColor, int caretLineTransp);

bool isDarkMode();

std::vector<std::string> getOpenedFiles();

void setStyles(UserSettings& settings);

void clearWindow(int view, bool clearIndicators = true);

void clearMarks(int view, intptr_t startLine, intptr_t length);
intptr_t getPrevUnmarkedLine(int view, intptr_t startLine, int markMask);
intptr_t getNextUnmarkedLine(int view, intptr_t startLine, int markMask);

std::pair<intptr_t, intptr_t> getMarkedSection(int view, intptr_t startLine, intptr_t endLine, int markMask,
        bool excludeNewLine = false);
std::vector<int> getMarkers(int view, intptr_t startLine, intptr_t length, int markMask, bool clearMarkers = true);
void setMarkers(int view, intptr_t startLine, const std::vector<int>& markers);

void unhideAllLines(int view);
void unhideLinesInRange(int view, intptr_t line, intptr_t length);
void hideLinesOutsideRange(int view, intptr_t startLine, intptr_t endLine);
void hideLines(int view, int hideMarkMask, bool hideUnmarked);

bool isAdjacentAnnotation(int view, intptr_t line, bool down);
bool isAdjacentAnnotationVisible(int view, intptr_t line, bool down);

void clearAnnotations(int view, intptr_t startLine, intptr_t length);

std::vector<char> getText(int view, intptr_t startPos, intptr_t endPos);
std::vector<char> getLineText(int view, intptr_t line, bool includeEOL = false);

intptr_t replaceText(int view, const std::string& txtToReplace, const std::string& replacementTxt,
    intptr_t searchStartLine = 0);

void addBlankSection(int view, intptr_t line, intptr_t length, intptr_t selectionMarkPosition = 0,
        const char* text = nullptr);
void addBlankSectionAfter(int view, intptr_t line, intptr_t length);

std::vector<intptr_t> getFoldedLines(int view);
void setFoldedLines(int view, const std::vector<intptr_t>& foldedLines);

void moveFileToOtherView();
std::vector<uint8_t> generateContentsSha256(int view, intptr_t startLine = 0, intptr_t endLine = -1);
