/*
 * NavBarPanel.h — ComparePlus "Navigation Bar" diff minimap (macOS).
 *
 * A docked side panel showing two columns (one per compared view) that render
 * a scaled, diff-colored histogram of the whole document: each line is a row
 * colored added/removed/changed/moved, with a viewport-indicator box and
 * click/drag/wheel scroll-sync. macOS port of the Windows NavDlg/NavDialog.
 *
 * The panel is a pure renderer driven by this small C++ API. It reads the
 * per-line diff markers straight from both Scintilla views (same data the
 * Windows NavDialog uses) and is given the diff colors by the caller, so it
 * has no dependency on ComparePlus's (file-static) settings globals.
 */
#pragma once

#ifdef __cplusplus
namespace NavBar
{
    struct Colors
    {
        int added;
        int removed;
        int changed;
        int moved;
        int background;   // initial only; rebuild() uses the live editor background
    };

    // Ensure the panel is registered + visible, rebuild its diff map from the
    // current per-line markers on both views, and redraw. Idempotent — safe to
    // call on the first compare and on every re-compare.
    void Show(const Colors& colors);

    // Hide the panel (keeps it registered for a fast re-show).
    void Hide();

    bool IsVisible();

    // If visible, rebuild with (possibly new) colors and redraw. Used on
    // theme/color changes.
    void Refresh(const Colors& colors);

    // Unregister the panel and release everything (plugin shutdown).
    void Shutdown();
}
#endif
