/*
 * Bridge functions linking the pure-C++ Engine to the Obj-C++ plugin.
 * Engine.cpp declares these as extern; this file provides the implementations
 * by calling Scintilla directly through the plugin's sendMessage callback.
 */

#import <Foundation/Foundation.h>
#include "NppPluginInterfaceMac.h"
#include "Scintilla.h"

// Access the global nppData (defined in ComparePlus.mm)
extern NppData nppData;

// ---------------------------------------------------------------------------
//  Per-view Scintilla redirect
//
//  On macOS the host gives every tab its own ScintillaView and routes the
//  MAIN/SUB plugin handles to whatever tab is *currently active* in each split
//  view. That makes it impossible, via the normal handle, to address a tab the
//  user has switched away from. When a redirect is set for a view, CallScintilla
//  for that view is dispatched straight to the supplied ScintillaView instead —
//  exactly as the host does internally (`[sv message:wParam:lParam:]`). Used by
//  clearAllCompares() to clear the originating compare tabs even after a switch
//  (issues #7/#9). Pass nil to restore the default routing.
// ---------------------------------------------------------------------------

@protocol _CPScintillaMessaging
- (sptr_t)message:(unsigned int)message wParam:(uptr_t)wParam lParam:(sptr_t)lParam;
@end

static __unsafe_unretained id<_CPScintillaMessaging> gSciRedirect[2] = { nil, nil };

// Identity-only; never owns the view. Always cleared (nil) synchronously after
// the redirected call sequence, so the target can't dangle.
void setScintillaRedirect(int viewNum, id scintillaView)
{
    if (viewNum == 0 || viewNum == 1)
        gSciRedirect[viewNum] = (id<_CPScintillaMessaging>)scintillaView;
}

static inline intptr_t sci(int viewNum, unsigned int uMsg, uintptr_t wParam = 0, intptr_t lParam = 0)
{
    if ((viewNum == 0 || viewNum == 1) && gSciRedirect[viewNum])
        return (intptr_t)[gSciRedirect[viewNum] message:uMsg wParam:(uptr_t)wParam lParam:(sptr_t)lParam];

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
