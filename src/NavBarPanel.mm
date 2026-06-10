/*
 * NavBarPanel.mm — ComparePlus "Navigation Bar" diff minimap (macOS).
 * See NavBarPanel.h. macOS port of the Windows src/NavDlg/NavDialog.{h,cpp}.
 *
 * Rendering model (mirrors the Windows NavDialog): for each of the two views,
 * walk every document line, read its diff marker via SCI_MARKERGET, map the
 * marker mask to a color, and resolve one color per panel pixel-row (diff
 * colors win over the background). Draw two side-by-side columns of 1px rows
 * scaled to the panel height — the direct analog of the Windows 1px bitmap +
 * StretchBlt. A translucent box marks the current viewport; click/drag/wheel
 * scroll both editors. The viewport box is refreshed by a light poll timer
 * (the plugin opts out of SCN_UPDATEUI, so we cannot rely on scroll events).
 */
#import <Cocoa/Cocoa.h>

#include <vector>

#include "NavBarPanel.h"
#include "CompareHelpers.h"   // CallScintilla, getView, nppData, MAIN/SUB_VIEW, marker masks, NPPM_DMM_*
#include "Scintilla.h"        // SCI_*, STYLE_DEFAULT

// ─────────────────────────────────────────────────────────────────────────────
//  Color helper: Scintilla COLORREF (0x00BBGGRR, red in low byte) → NSColor
// ─────────────────────────────────────────────────────────────────────────────
static inline NSColor* nsColorFromSci(int c)
{
    CGFloat r = ( c        & 0xFF) / 255.0;
    CGFloat g = ((c >>  8) & 0xFF) / 255.0;
    CGFloat b = ((c >> 16) & 0xFF) / 255.0;
    return [NSColor colorWithSRGBRed:r green:g blue:b alpha:1.0];
}

static const CGFloat kMargin = 1.0;   // border inset
static const CGFloat kGap    = 1.0;   // gap between the two columns

// ─────────────────────────────────────────────────────────────────────────────
//  The view
// ─────────────────────────────────────────────────────────────────────────────
@interface CPNavBarView : NSView
{
@public
    NavBar::Colors    _colors;
    std::vector<int>  _rows[2];     // resolved Scintilla color per pixel-row, per view
    intptr_t          _lineCount[2];
    int               _builtRows;   // pixel-row count the cache was built for
    bool              _dirty;
}
@end

@implementation CPNavBarView

- (instancetype)initWithFrame:(NSRect)f
{
    if ((self = [super initWithFrame:f]))
    {
        _colors      = {0xC6FFC6, 0xC6C6FF, 0x98E7E7, 0xFFE6CC, 0xFFFFFF};
        _lineCount[0] = _lineCount[1] = 0;
        _builtRows   = 0;
        _dirty       = true;
    }
    return self;
}

- (BOOL)isFlipped { return YES; }   // y == 0 at top, so document line 0 maps to the top

- (int)contentRows
{
    int h = (int)floor(self.bounds.size.height - 2 * kMargin);
    return (h < 1) ? 1 : h;
}

- (void)rebuild
{
    const int rows = [self contentRows];

    // Use the live editor background so the panel matches the current theme.
    NppHandle h0 = getView(MAIN_VIEW);
    int bg = h0 ? (int)CallScintilla(MAIN_VIEW, SCI_STYLEGETBACK, STYLE_DEFAULT, 0) : 0xFFFFFF;
    _colors.background = bg;

    for (int v = 0; v < 2; ++v)
    {
        NppHandle h   = getView(v);
        intptr_t  lc  = h ? CallScintilla(v, SCI_GETLINECOUNT, 0, 0) : 0;
        _lineCount[v] = lc;

        std::vector<int>& col = _rows[v];
        col.assign(rows, bg);

        if (lc <= 0)
            continue;

        for (intptr_t line = 0; line < lc; ++line)
        {
            const int m = (int)CallScintilla(v, SCI_MARKERGET, line, 0);
            if (!m)
                continue;

            int color;
            if      (m & MARKER_MASK_ADDED)   color = _colors.added;
            else if (m & MARKER_MASK_REMOVED) color = _colors.removed;
            else if (m & MARKER_MASK_MOVED)   color = _colors.moved;
            else if (m & MARKER_MASK_CHANGED) color = _colors.changed;
            else                              continue;

            int row = (int)((line * (intptr_t)rows) / lc);
            if (row < 0)         row = 0;
            else if (row >= rows) row = rows - 1;

            // Diff colors win over background; the first diff mapped to a row wins.
            if (col[row] == bg)
                col[row] = color;
        }
    }

    _builtRows = rows;
    _dirty     = false;
}

- (void)drawRect:(NSRect)dirtyRect
{
    const int rows = [self contentRows];
    if (_dirty || _builtRows != rows)
        [self rebuild];

    const NSRect b = self.bounds;

    // Background
    [nsColorFromSci(_colors.background) setFill];
    NSRectFill(b);

    CGFloat colW = (b.size.width - 2 * kMargin - kGap) / 2.0;
    if (colW < 1) colW = 1;
    const CGFloat xCol[2] = { kMargin, kMargin + colW + kGap };
    const CGFloat top     = kMargin;

    // Two columns of 1px diff rows
    for (int v = 0; v < 2; ++v)
    {
        const std::vector<int>& col = _rows[v];
        const int n = (int)col.size();
        for (int y = 0; y < n; ++y)
        {
            const int c = col[y];
            if (c == _colors.background)
                continue;                       // background already filled
            [nsColorFromSci(c) setFill];
            NSRectFill(NSMakeRect(xCol[v], top + y, colW, 1.0));
        }
    }

    // Viewport indicator — both views are aligned, so one box across the full
    // width tracks the current viewport. Map MAIN_VIEW's visible range to rows.
    if (getView(MAIN_VIEW) && _lineCount[MAIN_VIEW] > 0)
    {
        const intptr_t fv     = CallScintilla(MAIN_VIEW, SCI_GETFIRSTVISIBLELINE, 0, 0);
        const intptr_t los    = CallScintilla(MAIN_VIEW, SCI_LINESONSCREEN, 0, 0);
        intptr_t docTop = CallScintilla(MAIN_VIEW, SCI_DOCLINEFROMVISIBLE, fv, 0);
        intptr_t docBot = CallScintilla(MAIN_VIEW, SCI_DOCLINEFROMVISIBLE, fv + los, 0);
        if (docBot < docTop) docBot = docTop;

        const CGFloat lc   = (CGFloat)_lineCount[MAIN_VIEW];
        CGFloat yTop = top + (CGFloat)docTop * rows / lc;
        CGFloat yBot = top + (CGFloat)docBot * rows / lc;
        CGFloat hgt  = yBot - yTop;
        if (hgt < 2) hgt = 2;

        const NSRect box = NSMakeRect(kMargin, yTop, b.size.width - 2 * kMargin, hgt);
        [[NSColor colorWithSRGBRed:0.20 green:0.45 blue:0.95 alpha:0.18] setFill];
        NSRectFill(box);
        [[NSColor colorWithSRGBRed:0.20 green:0.45 blue:0.95 alpha:0.55] setStroke];
        NSFrameRectWithWidth(box, 1.0);
    }
}

// ── Interaction: scroll both editors ─────────────────────────────────────────
- (void)scrollToY:(CGFloat)y
{
    const int rows = [self contentRows];
    CGFloat frac = (y - kMargin) / (CGFloat)rows;
    if (frac < 0) frac = 0; else if (frac > 1) frac = 1;

    for (int v = 0; v < 2; ++v)
    {
        if (!getView(v) || _lineCount[v] <= 0)
            continue;

        intptr_t docLine = (intptr_t)(frac * (CGFloat)_lineCount[v]);
        if (docLine >= _lineCount[v]) docLine = _lineCount[v] - 1;

        const intptr_t los     = CallScintilla(v, SCI_LINESONSCREEN, 0, 0);
        intptr_t       visLine = CallScintilla(v, SCI_VISIBLEFROMDOCLINE, docLine, 0) - los / 2;
        if (visLine < 0) visLine = 0;

        CallScintilla(v, SCI_SETFIRSTVISIBLELINE, visLine, 0);
    }
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent*)e
{
    [self scrollToY:[self convertPoint:e.locationInWindow fromView:nil].y];
}

- (void)mouseDragged:(NSEvent*)e
{
    [self scrollToY:[self convertPoint:e.locationInWindow fromView:nil].y];
}

- (void)scrollWheel:(NSEvent*)e
{
    intptr_t lines = (intptr_t)llround(e.scrollingDeltaY);
    if (lines == 0)
        lines = (e.scrollingDeltaY > 0) ? 1 : (e.scrollingDeltaY < 0 ? -1 : 0);
    if (lines == 0)
        return;

    for (int v = 0; v < 2; ++v)
    {
        if (!getView(v))
            continue;
        intptr_t fv = CallScintilla(v, SCI_GETFIRSTVISIBLELINE, 0, 0) - lines;
        if (fv < 0) fv = 0;
        CallScintilla(v, SCI_SETFIRSTVISIBLELINE, fv, 0);
    }
    [self setNeedsDisplay:YES];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
//  Controller (file-static; one panel instance for the plugin's lifetime)
// ─────────────────────────────────────────────────────────────────────────────
static CPNavBarView *gView    = nil;
static uint64_t      gHandle  = 0;     // NPPM_DMM_REGISTERPANEL handle; 0 = not docked
static NSPanel      *gFloat   = nil;   // floating fallback for pre-docking hosts
static bool          gVisible = false;
static NSTimer      *gTimer   = nil;
static intptr_t      gLastFV[2] = { -1, -1 };

static void ensureView()
{
    if (gView) return;
    gView = [[CPNavBarView alloc] initWithFrame:NSMakeRect(0, 0, 120, 600)];
    gView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
}

static NSPanel* ensureFloating()
{
    if (gFloat) return gFloat;
    ensureView();
    NSRect frame = NSMakeRect(120, 120, 150, 640);
    NSUInteger mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                      NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow;
    gFloat = [[NSPanel alloc] initWithContentRect:frame styleMask:mask
                                          backing:NSBackingStoreBuffered defer:NO];
    gFloat.title              = @"ComparePlus NavBar";
    gFloat.releasedWhenClosed = NO;
    gFloat.hidesOnDeactivate  = NO;
    gView.frame = ((NSView*)gFloat.contentView).bounds;
    [gFloat.contentView addSubview:gView];
    [[NSNotificationCenter defaultCenter]
        addObserverForName:NSWindowWillCloseNotification object:gFloat queue:nil
                usingBlock:^(NSNotification*){ gVisible = false; }];
    return gFloat;
}

static void startTimer()
{
    if (gTimer) return;
    gTimer = [NSTimer scheduledTimerWithTimeInterval:0.12 repeats:YES block:^(NSTimer*) {
        if (!gVisible || !gView)
            return;
        intptr_t fv0 = CallScintilla(MAIN_VIEW, SCI_GETFIRSTVISIBLELINE, 0, 0);
        intptr_t fv1 = CallScintilla(SUB_VIEW,  SCI_GETFIRSTVISIBLELINE, 0, 0);
        if (fv0 != gLastFV[0] || fv1 != gLastFV[1])
        {
            gLastFV[0] = fv0;
            gLastFV[1] = fv1;
            [gView setNeedsDisplay:YES];   // viewport box recomputes in drawRect
        }
    }];
}

static void stopTimer()
{
    if (gTimer) { [gTimer invalidate]; gTimer = nil; }
}

void NavBar::Show(const Colors& colors)
{
    @autoreleasepool
    {
        ensureView();
        gView->_colors = colors;
        gView->_dirty  = true;

        if (gHandle == 0 && gFloat == nil)
        {
            intptr_t h = nppData._sendMessage(nppData._nppHandle, NPPM_DMM_REGISTERPANEL,
                                              (uintptr_t)(__bridge void*)gView,
                                              (intptr_t)"ComparePlus NavBar");
            if (h > 0) gHandle = (uint64_t)h;
            else       ensureFloating();
        }

        if (gHandle > 0)
            nppData._sendMessage(nppData._nppHandle, NPPM_DMM_SHOWPANEL, (uintptr_t)gHandle, 0);
        else if (gFloat)
            [gFloat orderFront:nil];

        gVisible   = true;
        gLastFV[0] = gLastFV[1] = -1;
        [gView setNeedsDisplay:YES];
        startTimer();
    }
}

void NavBar::Hide()
{
    if (gHandle > 0)
        nppData._sendMessage(nppData._nppHandle, NPPM_DMM_HIDEPANEL, (uintptr_t)gHandle, 0);
    else if (gFloat)
        [gFloat orderOut:nil];

    gVisible = false;
    stopTimer();
}

bool NavBar::IsVisible()
{
    return gVisible;
}

void NavBar::Refresh(const Colors& colors)
{
    if (!gVisible || !gView)
        return;
    gView->_colors = colors;
    gView->_dirty  = true;
    [gView setNeedsDisplay:YES];
}

void NavBar::Shutdown()
{
    stopTimer();
    if (gHandle > 0)
    {
        nppData._sendMessage(nppData._nppHandle, NPPM_DMM_UNREGISTERPANEL, (uintptr_t)gHandle, 0);
        gHandle = 0;
    }
    if (gFloat) { [gFloat close]; gFloat = nil; }
    gView    = nil;
    gVisible = false;
}
