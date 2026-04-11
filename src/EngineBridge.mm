/*
 * Bridge functions linking the pure-C++ Engine to the Obj-C++ plugin.
 * Engine.cpp declares these as extern; this file provides the implementations
 * by calling Scintilla directly through the plugin's sendMessage callback.
 */

#include "NppPluginInterfaceMac.h"
#include "Scintilla.h"

// Access the global nppData (defined in ComparePlus.mm)
extern NppData nppData;

static inline intptr_t sci(int viewNum, unsigned int uMsg, uintptr_t wParam = 0, intptr_t lParam = 0)
{
    NppHandle h = (viewNum == 0) ? nppData._scintillaMainHandle : nppData._scintillaSecondHandle;
    return nppData._sendMessage(h, uMsg, wParam, lParam);
}

// --- CallScintilla (used by CompareHelpers.h and Engine.cpp) ---

intptr_t CallScintilla(int viewNum, unsigned int uMsg, uintptr_t wParam, intptr_t lParam)
{
    return sci(viewNum, uMsg, wParam, lParam);
}

// --- Functions declared extern in Engine.cpp ---

intptr_t getLineStart(int view, intptr_t line)
{
    return sci(view, SCI_POSITIONFROMLINE, line, 0);
}

intptr_t getLineEnd(int view, intptr_t line)
{
    return sci(view, SCI_GETLINEENDPOSITION, line, 0);
}

intptr_t getLinesCount(int view)
{
    return sci(view, SCI_GETLINECOUNT, 0, 0);
}

bool isLineEmpty(int view, intptr_t line)
{
    return ((sci(view, SCI_GETLINEENDPOSITION, line, 0) -
             sci(view, SCI_POSITIONFROMLINE, line, 0)) == 0);
}

bool isLineHidden(int view, intptr_t line)
{
    return (sci(view, SCI_GETLINEVISIBLE, line, 0) == 0);
}

bool isLineFolded(int view, intptr_t line)
{
    intptr_t foldParent = sci(view, SCI_GETFOLDPARENT, line, 0);
    return (foldParent >= 0 && sci(view, SCI_GETFOLDEXPANDED, foldParent, 0) == 0);
}

bool getNextLineAfterFold(int view, intptr_t* line)
{
    intptr_t foldParent = sci(view, SCI_GETFOLDPARENT, *line, 0);
    if ((foldParent < 0) || (sci(view, SCI_GETFOLDEXPANDED, foldParent, 0) != 0))
        return false;
    *line = sci(view, SCI_GETLASTCHILD, foldParent, -1) + 1;
    return true;
}

intptr_t getUnhiddenLine(int view, intptr_t line)
{
    return sci(view, SCI_DOCLINEFROMVISIBLE,
               sci(view, SCI_VISIBLEFROMDOCLINE, line, 0), 0);
}

// getText, markTextAsChanged, clearChangedIndicator, clearWindow
// are defined in CompareHelpers.mm (which Engine.cpp also links against)
