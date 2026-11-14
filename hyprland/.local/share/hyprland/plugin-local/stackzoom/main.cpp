// stackzoom: the zoomed-out work view of a monitor's workspaces (ALT + Tab,
// bindings.lua).
//
// Every workspace of the monitor that has windows is a row, and the view
// draws back until about two of them fit on the screen (further back or
// closer with ALT + minus and ALT + ^). The rows lie the way
// the workspaces do on the scrolling layout, where each is a strip and
// ALT + J/K goes up and down between them: under one another. On any other
// layout there is no such view (toggle() answers false, and the binding
// shows the window carousel instead). Nothing is resized and nothing is
// a picture: the windows are drawn smaller by the compositor, the pointer is
// mapped back into them, and they take the mouse and the keyboard as they
// always do. The bar and every other layer stay as they are.
//
// Stacked strips are one plane. A strip slides its windows across the monitor
// to keep the focused column in sight; in the view that would carry one row
// along under the others. So a strip's row is drawn in the strip's own
// coordinates, its columns centred on the middle of the screen: the windows
// stay where they are, the view travels over them, and the rows lie
// symmetrically over one another (one window above three is above the one
// in the middle).
//
// The desktop HUD (clock, readouts) is faded out while the view is up: the
// rows are drawn over it and it would only show through between them.
//
// How: the renderer's own scale and translate modifiers around the windows of
// each row, a pointer transformer (the cursor is drawn where it is, the
// position the input code sees is the one inside the row), and the window
// hit test narrowed to the row under the pointer.
//
// Written against Hyprland 0.57.2. The hooked functions are looked up by
// their exact mangled names: on any other build they are not found and the
// plugin stays idle (toggle() answers false, the binding falls back).

#define WLR_USE_UNSTABLE

// The pass keeps the damage each of its elements is drawn through to itself;
// the rows need it widened (CZoomRow below).
// Whatever Pass.hpp includes comes first, so that only the pass itself is opened.
#include <hyprland/src/defines.hpp>
#include <hyprland/src/render/pass/PassElement.hpp>
#define private public
#include <hyprland/src/render/pass/Pass.hpp>
#undef private

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/ViewHitTester.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprland/src/desktop/view/Popup.hpp>
#include <hyprland/src/desktop/view/Subsurface.hpp>
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowBackend.hpp>
#include <hyprland/src/desktop/view/window/WindowEffectsController.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/layout/algorithm/Algorithm.hpp>
#include <hyprland/src/layout/algorithm/TiledAlgorithm.hpp>
#include <hyprland/src/layout/space/Space.hpp>
#include <hyprland/src/layout/supplementary/WorkspaceAlgoMatcher.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/pointer/PointerManager.hpp>
#include <hyprland/src/pointer/PointerTransformer.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/protocols/core/Subcompositor.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/pass/PassElement.hpp>
#include <hyprland/src/render/pass/RectPassElement.hpp>
#include <hyprland/src/render/pass/RendererHintsPassElement.hpp>
#include <hyprland/src/render/scene/SceneSelection.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/state/WorkspaceState.hpp>
#include <hyprland/src/workspace/HLWorkspace.hpp>

extern "C" {
#include <lauxlib.h>
#include <lua.h>
}

#include <dlfcn.h>

#include <algorithm>
#include <cmath>
#include <format>
#include <functional>
#include <string>
#include <vector>

namespace {

    HANDLE PHANDLE = nullptr;

    // How far the view draws back: windows are shown at this share of their
    // size. From there it goes further back or closer in steps (zoom()),
    // each this many times the one before, no further than the two ends.
    constexpr double ZOOM       = 0.5;
    constexpr double ZOOM_STEP  = 1.25;
    constexpr int    ZOOM_FAR   = -4; // 0.2
    constexpr int    ZOOM_CLOSE = 3;  // 0.98: next to the desktop's own size
    // The scale goes over to a new step at this rate.
    constexpr double ZOOM_RATE = 14.0;
    // Logical pixels between two rows, on top of the gaps the rows have already.
    constexpr double ROW_GAP = 0.0;
    // Milliseconds the view takes out and back in.
    constexpr double OPEN_MS  = 240.0;
    constexpr double CLOSE_MS = 190.0;
    // The camera follows the focus as a critically damped spring of this rate.
    constexpr double FOLLOW_RATE = 15.0;
    // Logical pixels kept free beside the widest row when the view follows the focus to its end.
    constexpr double EDGE = 24.0;
    // How dark the wallpaper gets behind the rows.
    constexpr double DIM = 0.38;

    using steady_tp = Time::steady_tp;

    // Layers of these namespaces are the desktop HUD (quickshell hud: the
    // scene and the glass panes under it).
    constexpr const char* HUD_LAYERS[] = {"hud-overlay", "hud-glass"};

    // A tiled window of a strip and the x the layout has given it.
    struct SPlace {
        PHLWINDOWREF window;
        double       x = 0;
    };

    // Where a row lies sideways in the plane. A strip's row is held by the
    // middle of its columns, wherever the layout has slid them on the monitor.
    struct SStrip {
        PHLWORKSPACEREF ws;
        bool            held  = false; // has columns to be held by
        double          left = 0, right = 0; // where the columns are heading for: first edge, last edge
        double          rest  = 0; // the shift that centres them
        std::vector<SPlace> places; // the columns' windows and where they were, to tell a jump by
        double          shift = 0; // added to the x of the row's windows
        double          ease  = 0; // what is left of a change of the columns, run out over a few frames
    };

    // The scene geometry of a view at this instant. Everything in logical
    // pixels; `world` is the plane the rows lie in: x as on the monitor and y
    // running down through the rows.
    struct SGeom {
        Vector2D pos;       // monitor origin
        double   W = 0, H = 0;
        double   top = 0;   // reserved at the top (the bar)
        double   Hu  = 0;   // height of a row: the monitor less its reserved bands
        double   P   = 0;   // from one row to the next, when they are stacked
        Vector2D pitch;     // from one row's origin to the next
        double   s   = 1;   // scale now
        Vector2D C;         // the screen point the camera looks through
        Vector2D cam;       // the world point seen there now
        int      active = 0;
        int      n      = 0;
        std::vector<double> shift; // per row: added to the x of its windows now
    };

    // One zoomed monitor.
    struct SView {
        PHLMONITORREF   mon;
        bool            open = false;
        double          z = 0, zFrom = 0, zTo = 0; // 0 = the desktop as it is, 1 = drawn back
        double          zoom = ZOOM; // the share of their size the windows have when drawn back, now
        steady_tp       zStart;
        Vector2D        cam, vel, target; // world coordinates, logical pixels
        bool            camSet    = false;
        bool            animating = false;
        bool            settled   = false; // came to rest in this frame
        steady_tp       last;
        bool            lastSet = false;
        PHLWORKSPACEREF locked; // the row the pointer stays in while a button is held
        std::vector<PHLWORKSPACEREF> forced; // workspaces told to draw though not shown
        std::vector<PHLWORKSPACEREF> rows;   // the rows of the last step, top to bottom
        std::vector<SStrip>          strips;
        std::vector<PHLLSREF>        hud; // desktop HUD layers the view faded out
        bool                         undimmed = false; // the rows' windows have their dim taken off

        // The frame as the last step left it: what is drawn, what the
        // pointer is mapped through and where a change to a window shows.
        // `rows` above are its rows.
        bool                  framed = false;
        SGeom                 geom;
        std::vector<Vector2D> at;    // per row: where its monitor origin lands on the screen
        std::vector<char>     drawn; // per row: in sight
    };

    // Only what a change touches is drawn again (see "Damage"). Off, every
    // frame of the view is the whole monitor: for comparing the two.
    bool g_precise = true;

    // What the frames of the views came to since stats() last asked.
    struct {
        uint64_t frames = 0;
        double   pixels = 0; // drawn through the damage, summed over the frames
    } g_stats;

    // The camera on the focused window itself, in the middle of the screen,
    // wherever that leaves the rows (see cameraTarget). Kept from one
    // opening of the view to the next.
    bool g_centred = false;

    // How many steps closer (or, below 0, further back) than ZOOM the views
    // are to be. Kept from one opening of the view to the next.
    int g_zoomStep = 0;

    double zoomGoal() {
        return ZOOM * std::pow(ZOOM_STEP, g_zoomStep);
    }

    std::vector<UP<SView>> g_views;
    int                    g_buttons = 0;

    // What the transformer made of the pointer the last time it was asked.
    struct {
        bool            zoomed = false; // on a zoomed monitor
        Vector2D        raw, out;
        PHLMONITORREF   mon;
        PHLWORKSPACEREF row;
    } g_pointer;

    SP<Pointer::CPointerTransformer> g_transformer;
    std::vector<CHyprSignalListener> g_listeners;

    double easeOut(double t) {
        t = std::clamp(t, 0.0, 1.0);
        const double u = 1.0 - t;
        return 1.0 - u * u * u;
    }

    bool near(const Vector2D& a, const Vector2D& b) {
        return std::abs(a.x - b.x) < 0.75 && std::abs(a.y - b.y) < 0.75;
    }

    SView* viewFor(const PHLMONITOR& mon) {
        if (!mon)
            return nullptr;
        for (auto& v : g_views) {
            if (v->mon.lock() == mon)
                return v.get();
        }
        return nullptr;
    }

    // The rows of a monitor, top to bottom: its workspaces that have windows,
    // and the one it shows.
    std::vector<PHLWORKSPACE> rowsOf(const PHLMONITOR& mon) {
        std::vector<PHLWORKSPACE> rows;
        for (auto const& ref : State::Workspace::state()->workspaces()) {
            const auto ws = ref.lock();
            if (!ws || ws->type() != Workspace::eWorkspaceType::NORMAL || ws->m_monitor.lock() != mon)
                continue;
            if (ws != mon->m_activeWorkspace && ws->getWindowCount() == 0)
                continue;
            rows.emplace_back(ws);
        }
        std::ranges::sort(rows, [](const PHLWORKSPACE& a, const PHLWORKSPACE& b) { return a->numberedID().value_or(UINT32_MAX) < b->numberedID().value_or(UINT32_MAX); });
        return rows;
    }

    int rowIndex(const std::vector<PHLWORKSPACE>& rows, const PHLWORKSPACE& ws) {
        for (size_t i = 0; i < rows.size(); ++i) {
            if (rows[i] == ws)
                return sc<int>(i);
        }
        return -1;
    }

    // Whether the workspace is a strip that runs off the screen. Only then do
    // the workspaces lie above each other.
    bool isStrip(const PHLWORKSPACE& ws) {
        const auto SPACE = ws->space();
        if (!SPACE || !SPACE->algorithm() || !SPACE->algorithm()->tiledAlgo())
            return false;
        return Layout::Supplementary::algoMatcher()->getNameForTiledAlgo(SPACE->algorithm()->tiledAlgo().get()) == "scrolling";
    }

    double shiftOf(const SView& v, const PHLWORKSPACE& ws) {
        for (auto const& s : v.strips) {
            if (s.ws.lock() == ws)
                return s.shift;
        }
        return 0.0;
    }

    // Where a window of the row belongs in the plane is its goal plus this
    // (the shift of this frame may still be easing over to it).
    double restOf(const SView& v, const PHLWORKSPACE& ws) {
        for (auto const& s : v.strips) {
            if (s.ws.lock() == ws)
                return s.rest;
        }
        return 0.0;
    }

    // Has the workspace lay its windows out for the monitor it is on now.
    // Hyprland does that for the workspace a monitor shows and leaves the
    // others for when they are next looked at: one that was taken to another
    // monitor while out of sight (a screen plugged in or pulled, which moves
    // every workspace bound to it) keeps its tiled windows at the places and
    // sizes the old monitor gave them. On the desktop nobody sees that. As a
    // row it was drawn off the screen or across the rows beside it.
    void settle(const PHLWORKSPACE& ws) {
        if (ws && ws->space())
            ws->space()->recalculate();
    }

    // Brings every row's place in the plane up to date. True while one is
    // still easing over to a new anchor.
    bool placeStrips(SView& v, const std::vector<PHLWORKSPACE>& rows, double dt) {
        std::erase_if(v.strips, [&rows](const SStrip& s) { return rowIndex(rows, s.ws.lock()) < 0; });

        bool easing = false;
        for (auto const& ws : rows) {
            auto       it    = std::ranges::find_if(v.strips, [&ws](const SStrip& s) { return s.ws.lock() == ws; });
            const bool FRESH = it == v.strips.end();
            if (FRESH) {
                it     = v.strips.emplace(v.strips.end());
                it->ws = ws;
                // A row the view has not drawn yet: whatever happened to its
                // monitor since it was last shown, it is laid out for it now.
                const auto MON = ws->m_monitor.lock();
                if (!MON || ws != MON->m_activeWorkspace)
                    settle(ws);
            }
            auto& strip = *it;

            // The columns of the strip. Their move and resize animations are
            // cut short while the view is up: the layout slides a whole strip
            // across the monitor to keep the focused column in sight, each
            // window on a spring of its own, and no single shift of the row
            // takes that out again to the pixel, so the row shimmered and
            // jittered under every sideways step. Here the windows are where
            // they belong at once; what moves is the row (eased below) and
            // the view.
            const auto          GOAL_ = Desktop::View::IGeometric::GEOMETRIC_GOAL;
            const auto          NOW_  = Desktop::View::IGeometric::GEOMETRIC_CURRENT;
            bool                held  = false;
            double              left = 0, right = 0;
            std::vector<SPlace> places;
            if (isStrip(ws)) {
                for (auto const& w : Desktop::viewState()->windows()) {
                    if (!w || !w->mapped() || w->isHidden() || w->m_workspace != ws || w->isFloating() || Fullscreen::controller()->isFullscreen(w))
                        continue;
                    const auto GOAL = w->position(GOAL_);
                    const auto SIZE = w->size(GOAL_);
                    if (w->position(NOW_) != GOAL || w->size(NOW_) != SIZE) {
                        if (const auto TARGET = w->layoutTarget())
                            TARGET->warpPositionSize();
                    }
                    left  = held ? std::min(left, GOAL.x) : GOAL.x;
                    right = held ? std::max(right, GOAL.x + SIZE.x) : GOAL.x + SIZE.x;
                    held  = true;
                    places.emplace_back(w, GOAL.x);
                }
            }

            // With nothing to hold the row by (empty, or one maximized window)
            // it is where the layout has it.
            double rest = 0.0;
            if (held) {
                const auto AREA = ws->space()->workArea();
                rest            = AREA.x + AREA.w / 2.0 - (left + right) / 2.0;
            }

            if (FRESH)
                strip.ease = 0.0;
            else {
                // How far the windows that were here before would jump in the
                // plane with the new centring: that much is taken up and run
                // out. Sliding the strip moves every goal and the centre
                // alike, which is no jump at all; a column more or less, or
                // another width, shifts them all by the same amount, the
                // middle one of these.
                std::vector<double> jumps;
                for (auto const& now : places) {
                    for (auto const& was : strip.places) {
                        if (was.window.lock() == now.window.lock())
                            jumps.emplace_back((was.x + strip.rest) - (now.x + rest));
                    }
                }
                if (jumps.empty())
                    strip.ease += strip.rest - rest;
                else {
                    std::ranges::sort(jumps);
                    strip.ease += jumps.size() == 2 ? (jumps[0] + jumps[1]) / 2.0 : jumps[jumps.size() / 2];
                }
            }
            strip.ease *= std::exp(-FOLLOW_RATE * dt);
            if (std::abs(strip.ease) < 0.3)
                strip.ease = 0.0;

            strip.held   = held;
            strip.left   = left;
            strip.right  = right;
            strip.rest   = rest;
            strip.places = std::move(places);
            strip.shift  = rest + strip.ease;
            easing       = easing || strip.ease != 0.0;
        }
        return easing;
    }

    // The camera with nothing drawn back: the shown row exactly as the desktop has it.
    Vector2D restCam(const SGeom& g) {
        return g.pitch * g.active + Vector2D{g.W / 2.0, g.Hu / 2.0};
    }

    SGeom geomOf(const SView& v, const PHLMONITOR& mon, const std::vector<PHLWORKSPACE>& rows) {
        SGeom      g;
        const auto BOX = mon->logicalBox();
        g.pos          = BOX.pos();
        g.W            = BOX.w;
        g.H            = BOX.h;
        g.top          = mon->m_reservedArea.top();
        g.Hu           = std::max(1.0, g.H - g.top - mon->m_reservedArea.bottom());
        g.P            = g.Hu + ROW_GAP;
        g.pitch        = Vector2D{0.0, g.P};
        g.n            = sc<int>(rows.size());
        g.active       = std::max(0, rowIndex(rows, mon->m_activeWorkspace));
        g.s            = 1.0 + (v.zoom - 1.0) * v.z;
        g.C            = {g.W / 2.0, g.top + g.Hu / 2.0};
        const auto REST = restCam(g);
        g.cam           = v.camSet ? REST + (v.cam - REST) * v.z : REST;
        // Only between stacked strips, and drawn back in with the view: at
        // the desktop every row is where the layout has it.
        for (auto const& ws : rows)
            g.shift.emplace_back(shiftOf(v, ws) * v.z);
        return g;
    }

    // Where the camera wants to be: on the focused window, but never so far up
    // or down that the screen shows less of the rows than it could. Centred
    // (g_centred), it is on the focused window and nothing holds it back.
    Vector2D cameraTarget(const SView& v, const std::vector<PHLWORKSPACE>& rows, const SGeom& g) {
        Vector2D   to      = restCam(g);
        const auto FOCUSED = Desktop::focusState()->window();
        if (FOCUSED && FOCUSED->mapped() && FOCUSED->m_workspace) {
            const int ROW = rowIndex(rows, FOCUSED->m_workspace);
            if (ROW >= 0) {
                const auto POS  = FOCUSED->position(Desktop::View::IGeometric::GEOMETRIC_GOAL) - g.pos;
                const auto SIZE = FOCUSED->size(Desktop::View::IGeometric::GEOMETRIC_GOAL);
                to              = {POS.x + SIZE.x / 2.0 + restOf(v, rows[ROW]), ROW * g.P + (POS.y - g.top) + SIZE.y / 2.0};
                if (g_centred)
                    return to;
            }
        }

        // Sideways the rows are centred on the middle of the screen. While the
        // widest of them fits, the view stays there and everything is in
        // sight, symmetric; past that it follows the focus, never further
        // than the end of the widest row.
        double widest = 0.0;
        for (auto const& s : v.strips) {
            if (s.held)
                widest = std::max(widest, s.right - s.left);
        }
        // (At the scale the view is going to: the camera sets off for where
        // it belongs then, while the scale is on its way.)
        const double ZOOM_TO = zoomGoal();
        const double ACROSS  = g.W / ZOOM_TO; // world width the screen shows
        const double REACH  = std::max(0.0, (widest + 2.0 * EDGE - ACROSS) / 2.0);
        to.x                = std::clamp(to.x, g.W / 2.0 - REACH, g.W / 2.0 + REACH);

        const double SPAN = g.n * g.P - ROW_GAP;   // all the rows
        const double SEEN = g.Hu / ZOOM_TO;        // world height the screen shows
        if (SPAN <= SEEN)
            to.y = SPAN / 2.0;
        else
            to.y = std::clamp(to.y, SEEN / 2.0, SPAN - SEEN / 2.0);
        return to;
    }

    void damage(const SView& v) {
        if (const auto MON = v.mon.lock())
            g_pHyprRenderer->damageMonitor(MON);
    }

    // Windows of a workspace that is not shown are told they are suspended and
    // stop drawing. In the view they are in sight.
    void wake(const std::vector<PHLWORKSPACE>& rows) {
        for (auto const& w : Desktop::viewState()->windows()) {
            if (!w || !w->mapped() || w->isHidden() || !w->m_workspace)
                continue;
            if (rowIndex(rows, w->m_workspace) >= 0)
                w->setSuspended(false);
        }
    }

    // decoration:dim_inactive marks the one window in use on a desktop. Drawn
    // back, every window is there to be read and picked: none is dimmed.
    // Hyprland sets the dim again on each change of focus, so this runs every
    // step while the view is open.
    void undim(SView& view, const std::vector<PHLWORKSPACE>& rows) {
        for (auto const& w : Desktop::viewState()->windows()) {
            if (!w || !w->mapped() || !w->m_workspace || rowIndex(rows, w->m_workspace) < 0)
                continue;
            if (w->presentation().dimPercent() != 0.F) {
                w->presentation().warpDimPercent(0.F);
                g_pHyprRenderer->damageWindow(w); // where the view shows it (hkDamageWindow)
            }
        }
        view.undimmed = true;
    }

    // The dim as Hyprland keeps it, for every window (a row's window may have
    // left the monitor since).
    void redim(SView& view) {
        if (!view.undimmed)
            return;
        view.undimmed = false;
        for (auto const& w : Desktop::viewState()->windows()) {
            if (w && w->mapped())
                w->presentation().refreshValues();
        }
    }

    void showHud(SView& view) {
        for (auto const& ref : view.hud) {
            if (const auto ls = ref.lock())
                *ls->alpha()[Desktop::View::LS_ALPHA_FADE] = 1.F;
        }
        view.hud.clear();
    }

    // Fades the desktop HUD of the monitor out with the view drawing back.
    // Layers that come after that are gone at once: the HUD unmaps under
    // windows and maps anew on an empty workspace, and a fade there is a
    // flash of its panes over the rows.
    void hideHud(SView& view, const PHLMONITOR& mon) {
        for (auto const& level : mon->m_layerSurfaceLayers) {
            for (auto const& ref : level) {
                const auto ls = ref.lock();
                if (!ls || std::ranges::find(HUD_LAYERS, ls->m_namespace) == std::end(HUD_LAYERS))
                    continue;
                auto& alpha = ls->alpha()[Desktop::View::LS_ALPHA_FADE];
                if (alpha->goal() != 0.F) {
                    if (view.z < 1.0)
                        *alpha = 0.F;
                    else
                        alpha->setValueAndWarp(0.F);
                }
                if (!std::ranges::any_of(view.hud, [&ls](const PHLLSREF& h) { return h.lock() == ls; }))
                    view.hud.emplace_back(ls);
            }
        }
    }

    // The view is gone: every workspace of the monitor is as Hyprland keeps it.
    void release(SView& view) {
        showHud(view);
        redim(view);
        // Exactly the ones the view set, wherever they have gone since.
        for (auto const& ref : view.forced) {
            if (const auto ws = ref.lock())
                ws->m_forceRendering = false;
        }
        view.forced.clear();
        const auto mon = view.mon.lock();
        if (!mon)
            return;
        for (auto const& w : Desktop::viewState()->windows()) {
            if (!w || !w->mapped() || !w->m_workspace || w->m_monitor.lock() != mon)
                continue;
            w->setSuspended(w->isHidden() || !w->m_workspace->visible());
        }
        g_pHyprRenderer->damageMonitor(mon);
    }

    void dropView(SView* view) {
        release(*view);
        std::erase_if(g_views, [view](const UP<SView>& v) { return v.get() == view; });
        if (g_views.empty())
            g_pointer = {};
    }

    // One step of the view, before its monitor is drawn.
    void step(SView& v, const PHLMONITOR& mon) {
        const auto NOW = Time::steadyNow();
        double     dt  = v.lastSet ? std::chrono::duration<double>(NOW - v.last).count() : 0.0;
        dt             = std::clamp(dt, 0.0, 0.1);
        v.last         = NOW;
        v.lastSet      = true;

        const double MS       = std::chrono::duration<double, std::milli>(NOW - v.zStart).count();
        const double T        = MS / (v.open ? OPEN_MS : CLOSE_MS);
        v.z                   = v.zFrom + (v.zTo - v.zFrom) * easeOut(T);
        const bool   ZOOMING  = T < 1.0;
        if (!ZOOMING)
            v.z = v.zTo;

        // Another step closer or further back: the scale runs over to it,
        // by ratio, so that each step looks the same length.
        const double ZOOM_TO = zoomGoal();
        if (v.zoom != ZOOM_TO) {
            const double LEFT = std::log(v.zoom / ZOOM_TO) * std::exp(-ZOOM_RATE * dt);
            v.zoom            = std::abs(LEFT) < 0.001 ? ZOOM_TO : ZOOM_TO * std::exp(LEFT);
        }
        const bool SCALING = v.zoom != ZOOM_TO;

        const auto ROWS = rowsOf(mon);
        for (auto const& ws : ROWS) {
            if (ws->m_forceRendering)
                continue;
            ws->m_forceRendering = true;
            v.forced.emplace_back(ws);
        }

        // A row more or less above the one in sight moves every row under it
        // by one place in the plane: stepping onto an empty workspace gives
        // it a row, leaving it takes the row away again. The camera goes
        // with the row it is over, so what is on the screen stays where it
        // is, and the way to the new focus is travelled, not jumped.
        if (v.camSet && !v.rows.empty()) {
            const double P    = geomOf(v, mon, ROWS).P;
            const int    LAST = sc<int>(v.rows.size()) - 1;
            const int    OVER = std::clamp(sc<int>(std::floor(v.cam.y / P)), 0, LAST);
            for (int d = 0; d <= LAST; ++d) {
                bool found = false;
                for (const int WAS : {OVER - d, OVER + d}) {
                    if (WAS < 0 || WAS > LAST)
                        continue;
                    const int IS = rowIndex(ROWS, v.rows[WAS].lock());
                    if (IS < 0)
                        continue;
                    v.cam.y += (IS - WAS) * P;
                    found = true;
                    break;
                }
                if (found)
                    break;
            }
        }
        const auto WERE = v.rows;
        v.rows.assign(ROWS.begin(), ROWS.end());

        // Hyprland goes over every window after a move or a change of
        // workspace and suspends the ones that are not on a shown one. A
        // suspended client stops drawing: its row would keep an old picture.
        if (v.open)
            wake(ROWS);

        // Back with the first frame of the way in, not after the last.
        if (v.open) {
            hideHud(v, mon);
            undim(v, ROWS);
        } else {
            showHud(v);
            redim(v);
        }

        const bool EASING = placeStrips(v, ROWS, dt);
        const auto G      = geomOf(v, mon, ROWS);
        // A held button is a drag or a selection inside a window: the view
        // holds still under it, and follows once it is let go.
        if (g_buttons == 0 || !v.camSet)
            v.target = cameraTarget(v, ROWS, G);

        bool moving = false;
        if (!v.camSet) {
            v.cam    = v.target;
            v.vel    = {};
            v.camSet = true;
        } else {
            const Vector2D D = v.cam - v.target;
            if (std::abs(D.x) < 0.3 && std::abs(D.y) < 0.3 && std::abs(v.vel.x) < 4.0 && std::abs(v.vel.y) < 4.0) {
                v.cam = v.target;
                v.vel = {};
            } else {
                const double   E   = std::exp(-FOLLOW_RATE * dt);
                const Vector2D TMP = (v.vel + D * FOLLOW_RATE) * dt;
                v.cam              = v.target + (D + TMP) * E;
                v.vel              = (v.vel - TMP * FOLLOW_RATE) * E;
                moving             = true;
            }
        }

        const bool WAS = v.animating;
        v.animating    = ZOOMING || SCALING || moving || EASING;
        v.settled      = WAS && !v.animating;

        // The frame this step makes. Rows that are drawn somewhere else than
        // in the frame before, or other rows, are a new picture of the whole
        // monitor; anything less is told by what changed (see "Damage").
        const auto            FRAME = geomOf(v, mon, ROWS);
        std::vector<Vector2D> at;
        std::vector<char>     drawn;
        for (int r = 0; r < FRAME.n; ++r) {
            const Vector2D O  = FRAME.pitch * r + Vector2D{FRAME.shift[r], 0.0};
            const Vector2D AT = {FRAME.C.x + (O.x - FRAME.cam.x) * FRAME.s, FRAME.C.y + (O.y - FRAME.top - FRAME.cam.y) * FRAME.s};
            at.emplace_back(AT);
            // Not when wholly above or below the screen.
            drawn.emplace_back(!(AT.y + (FRAME.top + FRAME.Hu) * FRAME.s < 0 || AT.y + FRAME.top * FRAME.s > FRAME.H));
        }
        const bool SAME = v.framed && v.geom.s == FRAME.s && v.geom.pos == FRAME.pos && v.geom.W == FRAME.W && v.geom.H == FRAME.H && v.at == at && v.drawn == drawn &&
            std::ranges::equal(WERE, v.rows, [](const PHLWORKSPACEREF& a, const PHLWORKSPACEREF& b) { return a.lock() == b.lock(); });
        v.geom   = FRAME;
        v.at     = std::move(at);
        v.drawn  = std::move(drawn);
        v.framed = true;
        if (!SAME)
            damage(v);
    }

    // ── Rendering ────────────────────────────────────────────────────────────

    // The pass culls what an opaque window covers and what lies off the
    // monitor, both judged where the windows really are, not where the view
    // draws them. This element turns that off for the frame.
    class CZoomMarker : public IPassElement {
      public:
        std::vector<UP<IPassElement>> draw(Render::CRenderContext& ctx) override {
            ++g_stats.frames;
            if (const auto MON = ctx.m_data.pMonitor.lock()) {
                ctx.m_data.damage.copy().intersect(CBox{{}, MON->m_transformedSize}).forEachRect([](const auto& r) { g_stats.pixels += sc<double>(r.x2 - r.x1) * (r.y2 - r.y1); });
            }
            return {};
        }
        bool needsLiveBlur(Render::CRenderContext&) override {
            return false;
        }
        bool needsPrecomputeBlur(Render::CRenderContext&) override {
            return false;
        }
        const char* passName() override {
            return "CStackZoomMarker";
        }
        ePassElementType type() override {
            return EK_CUSTOM;
        }
        bool undiscardable(Render::CRenderContext&) override {
            return true;
        }
        bool disableSimplification(Render::CRenderContext&) override {
            return true;
        }
        bool requiresFullDamage(Render::CRenderContext&) override {
            return !g_precise;
        }
    };

    // Everything in a pass is drawn through the frame's damage, and the pass
    // hands every element the same region, in the pixels of the output. The
    // elements do not agree on what it means under the modifiers: a surface
    // cuts it to its own box where the window really is and only then moves
    // the result (nothing at all for a column that is off the monitor, half
    // of one that is half off it, and the wrong part of any other), while a
    // border or a shadow cuts where it is drawn.
    //
    // This element stands before the windows of a row and, when the pass
    // reaches it, gives each element up to the row's end the damage in the
    // space it cuts in: for a surface, the damage taken back through the
    // row's modifiers. What is damaged on the output is not touched.
    class CZoomRow : public IPassElement {
      public:
        CZoomRow() = default; // the end of a row
        CZoomRow(double scale, const Vector2D& move) : m_begin(true), m_scale(scale), m_move(move) {}

        std::vector<UP<IPassElement>> draw(Render::CRenderContext& ctx) override {
            if (!m_begin || m_scale <= 0.0)
                return {};

            // Two pixels over: the way back does not land on whole pixels.
            const CRegion& SEEN = ctx.m_data.damage;
            const CRegion  REAL = SEEN.copy().translate(-m_move).scale(sc<float>(1.0 / m_scale)).expand(2);
            // For the kinds that cut either way, by what they are asked to draw.
            const CRegion  BOTH = REAL.copy().add(SEEN);

            for (auto* pass : {ctx.m_currentPass, &ctx.m_pass}) {
                if (!pass)
                    continue;
                auto& elements = pass->m_passElements;
                auto  self     = std::ranges::find_if(elements, [this](const auto& e) { return e.element.get() == this; });
                if (self == elements.end())
                    continue;
                for (auto it = std::next(self); it != elements.end(); ++it) {
                    if (const auto END = dynamic_cast<CZoomRow*>(it->element.get()); END && !END->m_begin)
                        break;
                    switch (it->element->type()) {
                        case EK_SURFACE: it->elementDamage = REAL; break;
                        case EK_TEXTURE:
                        case EK_TEXTURE_MATTE:
                        case EK_RECT: it->elementDamage = BOTH; break;
                        default: break; // drawn where it is seen: as the pass gave it
                    }
                }
                break;
            }
            return {};
        }
        bool needsLiveBlur(Render::CRenderContext&) override {
            return false;
        }
        bool needsPrecomputeBlur(Render::CRenderContext&) override {
            return false;
        }
        const char* passName() override {
            return "CStackZoomRow";
        }
        ePassElementType type() override {
            return EK_CUSTOM;
        }
        bool undiscardable(Render::CRenderContext&) override {
            return true;
        }

      private:
        bool     m_begin = false;
        double   m_scale = 1.0;
        Vector2D m_move;
    };

    using tRenderWindows = void (*)(void*, Render::CRenderContext&, PHLMONITOR, PHLWORKSPACE, const steady_tp&, Render::eSceneMode);

    CFunctionHook* g_hookWindows           = nullptr;
    CFunctionHook* g_hookWindowsFullscreen = nullptr;

    void callWindows(bool fullscreen, void* self, Render::CRenderContext& ctx, PHLMONITOR mon, PHLWORKSPACE ws, const steady_tp& now, Render::eSceneMode mode) {
        const auto HOOK = fullscreen ? g_hookWindowsFullscreen : g_hookWindows;
        (*rc<tRenderWindows>(HOOK->m_original))(self, ctx, mon, ws, now, mode);
    }

    // Stands in for the drawing of the shown workspace's windows on a zoomed
    // monitor: all rows, each scaled and put in its place.
    bool renderRows(void* self, Render::CRenderContext& ctx, const PHLMONITOR& mon, const PHLWORKSPACE& ws, const steady_tp& now, Render::eSceneMode mode) {
        if (mode != Render::eSceneMode::MONITOR || !mon || !ws || ws != mon->m_activeWorkspace)
            return false;
        const auto VIEW = viewFor(mon);
        if (!VIEW || VIEW->z <= 0.0)
            return false;

        if (!VIEW->framed || VIEW->rows.empty())
            return false;
        const auto&  G     = VIEW->geom;
        const double SCALE = mon->m_scale;

        Render::IHyprRenderer::addPassElement(ctx, makeUnique<CZoomMarker>());

        CRectPassElement::SRectData shade;
        shade.box   = {0, 0, mon->m_transformedSize.x, mon->m_transformedSize.y};
        shade.color = CHyprColor(0, 0, 0, DIM * VIEW->z);
        Render::IHyprRenderer::addPassElement(ctx, makeUnique<CRectPassElement>(shade));

        for (size_t r = 0; r < VIEW->rows.size(); ++r) {
            const auto ROW = VIEW->rows[r].lock();
            if (!ROW || !VIEW->drawn[r])
                continue;

            const Vector2D MOVE = VIEW->at[r] * SCALE;
            Render::SRenderModifData modif;
            modif.modifs.emplace_back(Render::SRenderModifData::RMOD_TYPE_SCALE, sc<float>(G.s));
            modif.modifs.emplace_back(Render::SRenderModifData::RMOD_TYPE_TRANSLATE, MOVE);
            Render::IHyprRenderer::addPassElement(ctx, makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{modif}));
            Render::IHyprRenderer::addPassElement(ctx, makeUnique<CZoomRow>(G.s, MOVE));

            // The scene of one workspace: its windows wherever they are laid
            // out, whether or not the workspace is the one shown.
            callWindows(Fullscreen::controller()->hasFullscreen(ROW), self, ctx, mon, ROW, now, Render::eSceneMode::WORKSPACE_WINDOWS);

            Render::IHyprRenderer::addPassElement(ctx, makeUnique<CZoomRow>());
            Render::IHyprRenderer::addPassElement(ctx, makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{Render::SRenderModifData{}}));
        }
        return true;
    }

    void hkRenderWindows(void* self, Render::CRenderContext& ctx, PHLMONITOR mon, PHLWORKSPACE ws, const steady_tp& now, Render::eSceneMode mode) {
        if (!renderRows(self, ctx, mon, ws, now, mode))
            callWindows(false, self, ctx, mon, ws, now, mode);
    }

    void hkRenderWindowsFullscreen(void* self, Render::CRenderContext& ctx, PHLMONITOR mon, PHLWORKSPACE ws, const steady_tp& now, Render::eSceneMode mode) {
        if (!renderRows(self, ctx, mon, ws, now, mode))
            callWindows(true, self, ctx, mon, ws, now, mode);
    }

    // A window's blur is a piece of a blurred picture of what is behind it,
    // and Hyprland takes that piece from where the window really is: the
    // modifiers move the window and not the blur under it. Inside a row the
    // box is put through the modifiers here instead, and the draw runs
    // without them: window and blur both from the place the window is seen.
    using tTextureWithBlur = void (*)(void*, Render::CRenderContext&, SP<Render::ITexture>, const CBox&, const Render::GL::CHyprOpenGLImpl::STextureRenderData&);

    CFunctionHook* g_hookTextureWithBlur = nullptr;

    void hkTextureWithBlur(void* self, Render::CRenderContext& ctx, SP<Render::ITexture> tex, const CBox& box, const Render::GL::CHyprOpenGLImpl::STextureRenderData& data) {
        auto&      modif = ctx.m_data.renderModif;
        const bool ROW   = !g_views.empty() && modif.enabled && !modif.modifs.empty() && viewFor(ctx.m_data.pMonitor.lock());
        if (!ROW) {
            (*rc<tTextureWithBlur>(g_hookTextureWithBlur->m_original))(self, ctx, tex, box, data);
            return;
        }

        CBox drawn = box;
        modif.applyToBox(drawn);
        auto scaled  = data;
        scaled.round = sc<int>(std::round(data.round * modif.combinedScale()));

        // The draw is cut by the damage it is handed, which is where the
        // window is seen; what it does besides goes by the context's.
        const auto SAVED  = modif;
        const auto DAMAGE = ctx.m_data.damage;
        modif             = {};
        if (data.damage)
            ctx.m_data.damage = *data.damage;
        (*rc<tTextureWithBlur>(g_hookTextureWithBlur->m_original))(self, ctx, tex, drawn, scaled);
        ctx.m_data.damage = DAMAGE;
        modif             = SAVED;
    }

    // ── Pointer ──────────────────────────────────────────────────────────────

    // The pointer as the input code is to see it: on a zoomed monitor, the
    // point inside the row under the cursor, in that workspace's own
    // coordinates. Called for every Pointer::mgr()->position().
    struct SMapped {
        bool          zoomed = false;
        Vector2D      out;
        PHLMONITOR    mon;
        PHLWORKSPACE  row;
    };

    SMapped mapPoint(const Vector2D& raw) {
        SMapped m;
        m.out = raw;

        for (auto const& v : g_views) {
            const auto MON = v->mon.lock();
            if (!MON || v->z <= 0.0 || !MON->logicalBox().containsPoint(raw))
                continue;
            // A special workspace and the lock are drawn over the view as they are.
            if (MON->m_activeSpecialWorkspace || g_pSessionLockManager->isSessionLocked())
                return m;

            // Through the frame that is on the screen.
            if (!v->framed || v->rows.empty())
                return m;
            const auto&    G     = v->geom;
            const Vector2D WORLD = (raw - G.pos - G.C) / G.s + G.cam;

            m.zoomed = true;
            m.mon    = MON;

            int        row    = -1;
            const auto LOCKED = v->locked.lock();
            if (LOCKED) {
                for (size_t i = 0; i < v->rows.size(); ++i) {
                    if (v->rows[i].lock() == LOCKED)
                        row = sc<int>(i);
                }
            }
            if (row < 0) {
                const int AT = sc<int>(std::floor(WORLD.y / G.P));
                if (AT >= 0 && AT < G.n && WORLD.y - AT * G.P < G.Hu)
                    row = AT;
            }
            if (row < 0)
                return m; // between the rows or past them: no window there

            m.row = v->rows[row].lock();
            if (!m.row)
                return m;
            m.out = G.pos + WORLD - G.pitch * row + Vector2D{-G.shift[row], G.top};
            return m;
        }
        return m;
    }

    Vector2D transformPointer(Vector2D raw) {
        const auto M     = mapPoint(raw);
        g_pointer.zoomed = M.zoomed;
        g_pointer.raw    = raw;
        g_pointer.out    = M.out;
        g_pointer.mon    = M.mon;
        g_pointer.row    = M.row;
        return M.out;
    }

    using tWindowAt     = PHLWINDOW (*)(void*, const Vector2D&, uint16_t, PHLWINDOW, PHLWORKSPACE);
    using tLayerAt      = SP<CWLSurfaceResource> (*)(void*, const Vector2D&, std::vector<PHLLSREF>*, Vector2D*, PHLLS*, bool);
    using tLayerPopupAt = SP<CWLSurfaceResource> (*)(void*, const Vector2D&, PHLMONITOR, Vector2D*, PHLLS*);

    using tFullscreenWindow = PHLWINDOW (*)(void*, PHLWORKSPACE, std::optional<bool>);
    using tMouseMove        = void (*)(void*, uint32_t, bool, bool, std::optional<Vector2D>, bool);

    CFunctionHook* g_hookWindowAt         = nullptr;
    CFunctionHook* g_hookLayerAt          = nullptr;
    CFunctionHook* g_hookLayerPopupAt     = nullptr;
    CFunctionHook* g_hookFullscreenWindow = nullptr;
    CFunctionHook* g_hookMouseMove        = nullptr;

    int g_inMouseMove = 0; // inside CInputManager::mouseMoveUnified

    // See hkWindowAt.
    struct {
        bool            pending = false;
        PHLWORKSPACEREF active;
        PHLWINDOWREF    window;
    } g_ideal;

    // Is this the pointer, as the transformer last handed it out on a zoomed monitor?
    bool isZoomedPointer(const Vector2D& pos) {
        return g_pointer.zoomed && near(pos, g_pointer.out);
    }

    // Every workspace of the monitor has its windows at the same coordinates:
    // only the row under the pointer is asked.
    PHLWINDOW hkWindowAt(void* self, const Vector2D& pos, uint16_t properties, PHLWINDOW ignore, PHLWORKSPACE workspace) {
        if (workspace || !isZoomedPointer(pos))
            return (*rc<tWindowAt>(g_hookWindowAt->m_original))(self, pos, properties, ignore, workspace);

        const auto ROW   = g_pointer.row.lock();
        PHLWINDOW  found = ROW ? (*rc<tWindowAt>(g_hookWindowAt->m_original))(self, pos, properties, ignore, ROW) : nullptr;

        // The pointer code is asking what lies under it. When the shown
        // workspace has a maximized window it goes on to take that one
        // whatever was found here: right on the shown row, wrong on any other.
        if (g_inMouseMove > 0 && (properties & Desktop::View::FOLLOW_MOUSE_CHECK)) {
            const auto MON    = g_pointer.mon.lock();
            const auto ACTIVE = MON ? MON->m_activeWorkspace : nullptr;
            // (It keeps a floating window that may lie over the maximized one;
            // asked here, before the answer is armed, as asking uses it up.)
            const bool KEPT = found && found->isFloating() && found->isAllowedOverFullscreen();
            if (ACTIVE && ACTIVE != ROW && !KEPT && Fullscreen::controller()->hasFullscreen(ACTIVE) &&
                Fullscreen::controller()->getFullscreenModes(ACTIVE).internal == Fullscreen::FSMODE_MAXIMIZED) {
                g_ideal.pending = true;
                g_ideal.active  = ACTIVE;
                g_ideal.window  = found;
            }
        }
        return found;
    }

    // The question that follows the one above: "the maximized window of the
    // shown workspace". Answered once with what is really under the pointer.
    PHLWINDOW hkFullscreenWindow(void* self, PHLWORKSPACE workspace, std::optional<bool> covering) {
        if (g_ideal.pending && g_inMouseMove > 0 && workspace && workspace == g_ideal.active.lock()) {
            g_ideal.pending = false;
            return g_ideal.window.lock();
        }
        return (*rc<tFullscreenWindow>(g_hookFullscreenWindow->m_original))(self, workspace, covering);
    }

    void hkMouseMove(void* self, uint32_t time, bool refocus, bool mouse, std::optional<Vector2D> overridePos, bool pointerOnly) {
        // Left as it was found whichever way the call ends.
        struct SInside {
            SInside() {
                g_ideal.pending = false;
                ++g_inMouseMove;
            }
            ~SInside() {
                --g_inMouseMove;
                g_ideal.pending = false;
            }
        } inside;
        (*rc<tMouseMove>(g_hookMouseMove->m_original))(self, time, refocus, mouse, overridePos, pointerOnly);
    }

    // Layers are drawn as they are, so they are hit where the cursor is.
    SP<CWLSurfaceResource> hkLayerAt(void* self, const Vector2D& pos, std::vector<PHLLSREF>* layers, Vector2D* coords, PHLLS* found, bool aboveLock) {
        const Vector2D AT = isZoomedPointer(pos) ? g_pointer.raw : pos;
        return (*rc<tLayerAt>(g_hookLayerAt->m_original))(self, AT, layers, coords, found, aboveLock);
    }

    SP<CWLSurfaceResource> hkLayerPopupAt(void* self, const Vector2D& pos, PHLMONITOR monitor, Vector2D* coords, PHLLS* found) {
        const Vector2D AT = isZoomedPointer(pos) ? g_pointer.raw : pos;
        return (*rc<tLayerPopupAt>(g_hookLayerPopupAt->m_original))(self, AT, monitor, coords, found);
    }

    // ── Damage ───────────────────────────────────────────────────────────────

    // Hyprland damages a surface where it really is, and not at all when that
    // is on a workspace not shown. In the view the window is seen somewhere
    // else, at another size: a change to it is damage there, the box it has
    // in its row put through the row's place in the frame. So a terminal
    // that prints redraws its own picture in the view and nothing else.
    //
    // Layers are drawn as they are and Hyprland's damage for them is right.
    // What moves every row (the view drawing back, the camera, a row more or
    // less) is damaged as a whole by step().
    using tDamageSurface = void (*)(void*, SP<CWLSurfaceResource>, double, double, double);
    using tDamageWindow  = void (*)(void*, PHLWINDOW, bool);
    using tDamageBox     = void (*)(void*, const CBox&, bool);
    using tCommitWindow  = void (*)(void*, bool);
    using tCommitSub     = void (*)(void*);
    using tCommitPopup   = void (*)(void*, bool);

    CFunctionHook* g_hookDamageSurface = nullptr;
    CFunctionHook* g_hookDamageWindow  = nullptr;
    CFunctionHook* g_hookDamageBox     = nullptr;
    CFunctionHook* g_hookCommitWindow  = nullptr;
    CFunctionHook* g_hookCommitSub     = nullptr;
    CFunctionHook* g_hookCommitPopup   = nullptr;

    // Whose surface: a window's (its own, a subsurface's or a popup's), a
    // layer's or the lock's (drawn as they are), or nobody's that is known.
    struct SOwner {
        PHLWINDOW window;
        bool      asIs  = false;
        bool      popup = false;
    };

    SOwner ownerOf(SP<CWLSurfaceResource> surface) {
        // A subsurface is asked for the surface it hangs from, and that one
        // again if it is a subsurface itself (the bound is against a ring).
        for (int hop = 0; hop < 8 && surface; ++hop) {
            const auto HLSURFACE = Desktop::View::CWLSurface::fromResource(surface);
            const auto VIEW      = HLSURFACE ? HLSURFACE->view() : nullptr;
            if (!VIEW)
                return {};
            switch (VIEW->type()) {
                case Desktop::View::VIEW_TYPE_WINDOW: return {.window = Desktop::View::CWindow::fromView(VIEW)};
                case Desktop::View::VIEW_TYPE_LAYER_SURFACE:
                case Desktop::View::VIEW_TYPE_LOCK_SCREEN: return {.asIs = true};
                case Desktop::View::VIEW_TYPE_POPUP: {
                    const auto POPUP = Desktop::View::CPopup::fromView(VIEW);
                    if (!POPUP)
                        return {};
                    if (const auto WINDOW = POPUP->windowOwner())
                        return {.window = WINDOW, .popup = true};
                    return {.asIs = POPUP->layerOwner() != nullptr};
                }
                case Desktop::View::VIEW_TYPE_SUBSURFACE: {
                    if (!surface->m_role || surface->m_role->role() != SURFACE_ROLE_SUBSURFACE)
                        return {};
                    const auto SUB = sc<CSubsurfaceRole*>(surface->m_role.get())->m_subsurface.lock();
                    surface        = SUB ? SUB->t1Parent() : nullptr;
                    break;
                }
                default: return {};
            }
        }
        return {};
    }

    // The view a window is a row of, and which row of its frame.
    struct SSeen {
        SView* view = nullptr;
        int    row  = -1;
    };

    SSeen seenIn(const PHLWINDOW& window) {
        if (!window || !window->m_workspace)
            return {};
        for (auto const& v : g_views) {
            for (size_t r = 0; r < v->rows.size(); ++r) {
                if (v->rows[r].lock() == window->m_workspace)
                    return {v.get(), sc<int>(r)};
            }
        }
        return {};
    }

    // Damages where the view shows a region of one of its rows; the region
    // in global logical pixels, as the row's workspace has it. `blurred`:
    // for what blurs the picture behind it as it is drawn (a floating
    // window, a popup), which needs that picture drawn a blur's reach
    // further out.
    void damageSeen(SView& v, int row, const CRegion& region, bool blurred) {
        const auto MON = v.mon.lock();
        if (!MON || region.empty())
            return;
        if (!g_precise || !v.framed || row < 0 || row >= sc<int>(v.at.size())) {
            g_pHyprRenderer->damageMonitor(MON);
            return;
        }
        if (!v.drawn[row])
            return;
        // A floating window of the row over the region blurs it as well.
        if (!blurred) {
            const auto WORKSPACE = v.rows[row].lock();
            for (auto const& w : Desktop::viewState()->windows()) {
                if (!w || !w->mapped() || w->isHidden() || !w->isFloating() || w->m_workspace != WORKSPACE)
                    continue;
                if (!region.copy().intersect(w->getFullWindowBoundingBox()).empty()) {
                    blurred = true;
                    break;
                }
            }
        }
        CRegion seen = region.copy();
        seen.translate(-MON->m_position).scale(sc<float>(MON->m_scale * v.geom.s)).translate(v.at[row] * MON->m_scale).expand(2);
        if (blurred)
            g_pHyprRenderer->expandBlurDamage(seen, 2.5F);
        MON->addDamage(seen);
    }

    // IHyprRenderer::damageSurface, for the surface of a row's window: the
    // same damage taken from the surface, put where the view shows it.
    void damageSurfaceSeen(const SSeen& at, const SOwner& owner, SP<CWLSurfaceResource> surface, double x, double y, double scale) {
        const auto HLSURFACE = Desktop::View::CWLSurface::fromResource(surface);
        const auto MON       = at.view->mon.lock();
        if (!HLSURFACE || !MON)
            return;
        const auto BOX = HLSURFACE->getSurfaceBoxGlobal();

        // A client that waits for its frame callback gets one.
        if (!surface->m_current.callbacks.empty() && BOX && !BOX->empty())
            MON->scheduleFrame(Aquamarine::IOutput::AQ_SCHEDULE_NEEDS_FRAME);

        CRegion region = HLSURFACE->computeDamage(BOX);
        if (region.empty())
            return;
        if (scale != 1.0)
            region.scale(sc<float>(scale));
        region.translate({x, y});
        damageSeen(*at.view, at.row, region, owner.popup || owner.window->isFloating());
    }

    void hkDamageSurface(void* self, SP<CWLSurfaceResource> surface, double x, double y, double scale) {
        if (g_views.empty() || !surface) {
            (*rc<tDamageSurface>(g_hookDamageSurface->m_original))(self, surface, x, y, scale);
            return;
        }
        const auto OWNER = ownerOf(surface);
        const auto AT    = OWNER.window ? seenIn(OWNER.window) : SSeen{};
        if (AT.view && g_precise) {
            // A floating window may reach onto the monitor beside: there it is as it is.
            if (OWNER.window->isFloating() && !OWNER.popup) {
                const auto DAMAGE = surface->m_current.damage.copy();
                const auto BUFFER = surface->m_current.bufferDamage.copy();
                damageSurfaceSeen(AT, OWNER, surface, x, y, scale);
                // (Taking the damage uses it up: the same again for the other.)
                surface->m_current.damage       = DAMAGE;
                surface->m_current.bufferDamage = BUFFER;
                (*rc<tDamageSurface>(g_hookDamageSurface->m_original))(self, surface, x, y, scale);
                return;
            }
            damageSurfaceSeen(AT, OWNER, surface, x, y, scale);
            return;
        }
        (*rc<tDamageSurface>(g_hookDamageSurface->m_original))(self, surface, x, y, scale);
        if (OWNER.asIs || (OWNER.window && !AT.view))
            return;
        // A row's window with the whole monitor asked for, or a surface of
        // nobody known: it may be seen anywhere.
        for (auto const& v : g_views) {
            if (!AT.view || AT.view == v.get())
                damage(*v);
        }
    }

    void hkDamageWindow(void* self, PHLWINDOW window, bool forceFull) {
        const auto AT = g_views.empty() ? SSeen{} : seenIn(window);
        if (!AT.view) {
            (*rc<tDamageWindow>(g_hookDamageWindow->m_original))(self, window, forceFull);
            return;
        }
        // A workspace that slides or fades has its windows somewhere between.
        if (const auto WORKSPACE = window->m_workspace; WORKSPACE->m_renderOffset->isBeingAnimated() || WORKSPACE->m_alpha->isBeingAnimated())
            damage(*AT.view);
        // As Hyprland takes the box, shadow and border included.
        CBox box = window->getFullWindowBoundingBox();
        box.translate(window->presentation().floatingOffset());
        box = window->effects().transformBoxForDamage(box);
        damageSeen(*AT.view, AT.row, CRegion{box}, window->isFloating());
        if (window->isFloating() || !g_precise)
            (*rc<tDamageWindow>(g_hookDamageWindow->m_original))(self, window, forceFull);
    }

    // The surface whose commit Hyprland is working through, and whose it is
    // (looked up when first asked).
    using tCommitState = void (*)(void*, void*);

    CFunctionHook* g_hookCommitState = nullptr;

    struct {
        CWLSurfaceResource* surface = nullptr;
        bool                known   = false;
        SOwner              owner;
    } g_committing;

    void hkCommitState(void* self, void* state) {
        const auto OUTER = g_committing;
        g_committing     = {.surface = rc<CWLSurfaceResource*>(self)};
        (*rc<tCommitState>(g_hookCommitState->m_original))(self, state);
        g_committing = OUTER;
    }

    // A box damaged by its place alone says nothing of what it belongs to.
    // Inside a commit it is known: whatever is damaged then is the
    // committing surface's (Hyprland damages the whole box of a surface that
    // asks for blur behind it on each of its commits, which terminals do,
    // shown or not). A row's window is damaged where the view has it and
    // nowhere else, a layer's where it is.
    //
    // Outside a commit (a decoration, an animation, another plugin) the box
    // may be any row's: every row has its windows at the same places, so it
    // is damaged in each row that is drawn, and where it is.
    void hkDamageBox(void* self, const CBox& box, bool skipFrameSchedule) {
        if (g_views.empty() || skipFrameSchedule || !g_precise) {
            (*rc<tDamageBox>(g_hookDamageBox->m_original))(self, box, skipFrameSchedule);
            if (!g_precise && !skipFrameSchedule) {
                for (auto const& v : g_views) {
                    if (const auto MON = v->mon.lock(); MON && MON->logicalBox().overlaps(box))
                        damage(*v);
                }
            }
            return;
        }

        if (g_committing.surface) {
            if (!g_committing.known) {
                g_committing.owner = ownerOf(g_committing.surface->m_self.lock());
                g_committing.known = true;
            }
            const auto& OWNER = g_committing.owner;
            // Its own only if it lies by the window: a listener of the
            // commit may damage what is somebody else's.
            const bool OWN = !OWNER.window || OWNER.popup || OWNER.window->getFullWindowBoundingBox().expand(64).overlaps(box);
            if ((OWNER.window || OWNER.asIs) && OWN) {
                const auto AT       = OWNER.window ? seenIn(OWNER.window) : SSeen{};
                const bool FLOATING = OWNER.window && OWNER.window->isFloating();
                if (AT.view)
                    damageSeen(*AT.view, AT.row, CRegion{box}, FLOATING || OWNER.popup);
                // (A floating window may reach onto the monitor beside: there it is as it is.)
                if (!AT.view || FLOATING)
                    (*rc<tDamageBox>(g_hookDamageBox->m_original))(self, box, skipFrameSchedule);
                return;
            }
        }

        (*rc<tDamageBox>(g_hookDamageBox->m_original))(self, box, skipFrameSchedule);
        const auto SAME = [&box](const CBox& other) {
            return std::abs(other.x - box.x) <= 1 && std::abs(other.y - box.y) <= 1 && std::abs(other.w - box.w) <= 1 && std::abs(other.h - box.h) <= 1;
        };
        for (auto const& v : g_views) {
            const auto MON = v->mon.lock();
            if (!MON || !v->framed || !MON->logicalBox().overlaps(box))
                continue;
            // To the pixel the box of a layer: that layer, drawn as it is.
            bool layer = false;
            for (auto const& level : MON->m_layerSurfaceLayers) {
                for (auto const& ref : level) {
                    const auto ls = ref.lock();
                    layer         = layer || (ls && SAME(CBox{ls->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT), ls->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT)}));
                }
            }
            if (layer)
                continue;
            for (size_t r = 0; r < v->rows.size(); ++r)
                damageSeen(*v, sc<int>(r), CRegion{box}, false);
        }
    }

    // Hyprland drops the commit of a window whose workspace is not shown
    // before it gets as far as damage. A row that is not the shown one is
    // in sight all the same: its commits are damage here.
    void commitUnshown(const SP<Desktop::View::CWLSurface>& hlSurface, const std::function<Vector2D()>& where, double scale) {
        const auto SURFACE = hlSurface ? hlSurface->resource() : nullptr;
        if (!SURFACE)
            return;
        const auto OWNER = ownerOf(SURFACE);
        if (!OWNER.window || !OWNER.window->mapped() || OWNER.window->isHidden() || !OWNER.window->m_workspace || OWNER.window->m_workspace->visible())
            return;
        const auto AT = seenIn(OWNER.window);
        if (!AT.view)
            return;
        if (!g_precise) {
            damage(*AT.view);
            return;
        }
        const auto pos   = where(); // asked only now: the surface is a mapped window's
        const bool WAITS = !SURFACE->m_current.callbacks.empty();
        const bool HAD   = !SURFACE->m_current.damage.empty() || !SURFACE->m_current.bufferDamage.empty();
        damageSurfaceSeen(AT, OWNER, SURFACE, pos.x, pos.y, scale);
        // Nothing new to show, but the client waits to be told a frame went
        // out before it draws again: only a frame that is drawn tells the
        // rows, so one is, of next to nothing.
        if (WAITS && !HAD)
            damageSeen(*AT.view, AT.row, CRegion{CBox{pos, Vector2D{1.0, 1.0}}}, false);
    }

    void hkCommitWindow(void* self, bool sync) {
        // Held over the original: a commit may be the window's last.
        const auto WINDOW = rc<Desktop::View::CWindow*>(self)->m_self.lock();
        (*rc<tCommitWindow>(g_hookCommitWindow->m_original))(self, sync);
        if (g_views.empty())
            return;
        if (WINDOW && WINDOW->mapped())
            commitUnshown(WINDOW->wlSurface(), [&WINDOW] { return WINDOW->position(Desktop::View::IGeometric::GEOMETRIC_GOAL); }, 1.0 / WINDOW->backend().surfaceScale());
    }

    // Before the original: it drops the commit of an unshown window's
    // surface untouched, and may destroy an orphaned popup.
    void hkCommitSub(void* self) {
        if (!g_views.empty()) {
            const auto SUB = rc<Desktop::View::CSubsurface*>(self);
            commitUnshown(SUB->wlSurface(), [SUB] { return SUB->coordsGlobal(); }, 1.0);
        }
        (*rc<tCommitSub>(g_hookCommitSub->m_original))(self);
    }

    void hkCommitPopup(void* self, bool ignoreSiblings) {
        if (!g_views.empty()) {
            const auto POPUP = rc<Desktop::View::CPopup*>(self);
            commitUnshown(POPUP->wlSurface(), [POPUP] { return POPUP->coordsGlobal(); }, 1.0);
        }
        (*rc<tCommitPopup>(g_hookCommitPopup->m_original))(self, ignoreSiblings);
    }

    // ── Control ──────────────────────────────────────────────────────────────

    bool g_ready = false; // all hooks are in

    PHLMONITOR monitorNamed(const char* name) {
        if (name && *name) {
            for (auto const& m : State::monitorState()->monitors()) {
                if (m && m->m_name == name)
                    return m;
            }
            return nullptr;
        }
        // The focused window's monitor: the one Hyprland calls focused follows the pointer.
        if (const auto WINDOW = Desktop::focusState()->window(); WINDOW && WINDOW->m_monitor)
            return WINDOW->m_monitor.lock();
        return Desktop::focusState()->monitor();
    }

    // The view is of strips lying under one another: a monitor whose shown
    // workspace is on another layout has none.
    bool hasStrips(const PHLMONITOR& mon) {
        return mon->m_activeWorkspace && isStrip(mon->m_activeWorkspace);
    }

    bool realFullscreen(const PHLMONITOR& mon) {
        const auto WS = mon->m_activeWorkspace;
        return WS && Fullscreen::controller()->hasFullscreen(WS) && Fullscreen::controller()->getFullscreenModes(WS).internal == Fullscreen::FSMODE_FULLSCREEN;
    }

    bool isOpen(const PHLMONITOR& mon) {
        const auto VIEW = viewFor(mon);
        return VIEW && VIEW->open;
    }

    bool setOpen(const PHLMONITOR& mon, bool open) {
        if (!g_ready || !mon || mon->isMirror())
            return false;

        for (size_t i = g_views.size(); i-- > 0;) {
            if (g_views[i]->mon.expired())
                dropView(g_views[i].get());
        }

        auto view = viewFor(mon);
        if (!view) {
            if (!open)
                return false;
            // A window in real fullscreen is drawn alone, past the scene: there is nothing to draw back from.
            if (realFullscreen(mon) || !hasStrips(mon))
                return false;
            view       = g_views.emplace_back(makeUnique<SView>()).get();
            view->mon  = mon;
            view->zoom = zoomGoal();
        }
        if (view->open == open)
            return true;

        view->open   = open;
        view->zFrom  = view->z;
        view->zTo    = open ? 1.0 : 0.0;
        view->zStart = Time::steadyNow();
        view->lastSet = false;
        if (open) {
            view->camSet = false; // taken from the focus on the first step
            wake(rowsOf(mon));
        }
        view->animating = true;
        g_pHyprRenderer->damageMonitor(mon);
        return true;
    }

    int luaToggle(lua_State* L) {
        const auto MON = monitorNamed(luaL_optstring(L, 1, nullptr));
        lua_pushboolean(L, setOpen(MON, !isOpen(MON)));
        return 1;
    }

    int luaOpen(lua_State* L) {
        lua_pushboolean(L, setOpen(monitorNamed(luaL_optstring(L, 1, nullptr)), true));
        return 1;
    }

    int luaClose(lua_State* L) {
        lua_pushboolean(L, setOpen(monitorNamed(luaL_optstring(L, 1, nullptr)), false));
        return 1;
    }

    int luaActive(lua_State* L) {
        lua_pushboolean(L, isOpen(monitorNamed(luaL_optstring(L, 1, nullptr))));
        return 1;
    }

    // probe(monitor, x, y): what a pointer at that point of the monitor (logical
    // pixels from its corner) would be over. For checking the mapping without
    // a pointer: workspace id, the point in that workspace, the window's title.
    int luaProbe(lua_State* L) {
        // A Lua error is a longjmp: the arguments are read before anything with a destructor exists.
        const char* const NAME = luaL_checkstring(L, 1);
        const double      X    = luaL_checknumber(L, 2);
        const double      Y    = luaL_checknumber(L, 3);
        const auto        MON  = monitorNamed(NAME);
        if (!MON || !g_ready)
            return 0;
        const auto M = mapPoint(MON->logicalBox().pos() + Vector2D{X, Y});
        if (!M.zoomed || !M.row)
            return 0;
        auto       tester = Desktop::viewState()->hitTest();
        const auto WINDOW = (*rc<tWindowAt>(g_hookWindowAt->m_original))(
            &tester, M.out, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS | Desktop::View::ALLOW_FLOATING, nullptr, M.row);
        lua_pushinteger(L, M.row->numberedID().value_or(0));
        lua_pushnumber(L, M.out.x - MON->logicalBox().x);
        lua_pushnumber(L, M.out.y - MON->logicalBox().y);
        if (WINDOW)
            lua_pushstring(L, WINDOW->metadata().title().c_str());
        else
            lua_pushnil(L);
        return 4;
    }

    // precise(on): whether only what changed is drawn again. For measuring
    // one against the other; answers what it is now.
    int luaPrecise(lua_State* L) {
        if (lua_gettop(L) >= 1) {
            g_precise = lua_toboolean(L, 1);
            for (auto const& v : g_views)
                damage(*v);
        }
        lua_pushboolean(L, g_precise);
        return 1;
    }

    // stats(): frames the views drew since the last call, and the megapixels
    // drawn through their damage in all of them. For measuring.
    // centred([on]) -> on. Without an argument it is switched over. A frame
    // is asked of every view, which then moves its camera to the new place.
    int luaCentred(lua_State* L) {
        g_centred = lua_isnoneornil(L, 1) ? !g_centred : lua_toboolean(L, 1);
        for (auto const& v : g_views)
            damage(*v);
        lua_pushboolean(L, g_centred);
        return 1;
    }

    // zoom([steps]) -> the share of their size the windows are shown at.
    // Steps above 0 are closer, below 0 further back; without an argument
    // nothing changes. The views run over to it from their next frame.
    int luaZoom(lua_State* L) {
        const int STEPS = sc<int>(luaL_optinteger(L, 1, 0));
        const int TO    = std::clamp(g_zoomStep + STEPS, ZOOM_FAR, ZOOM_CLOSE);
        if (TO != g_zoomStep) {
            g_zoomStep = TO;
            for (auto const& v : g_views) {
                // A view at rest has drawn no frame for a while: the run
                // starts with the frame this asks for, not somewhere along.
                if (!v->animating)
                    v->lastSet = false;
                damage(*v);
            }
        }
        lua_pushnumber(L, zoomGoal());
        return 1;
    }

    int luaStats(lua_State* L) {
        lua_pushinteger(L, sc<lua_Integer>(g_stats.frames));
        lua_pushnumber(L, g_stats.pixels / 1e6);
        g_stats = {};
        return 2;
    }

    void onRenderStage(const Event::SRenderStageEvent& e) {
        if (g_views.empty() || !e.monitor)
            return;
        const auto VIEW = viewFor(e.monitor);
        if (!VIEW)
            return;

        if (e.stage == RENDER_PRE) {
            // A window in real fullscreen is drawn alone, past the scene.
            // And a layout that is not a strip has no rows to lie in.
            if (VIEW->open && (realFullscreen(e.monitor) || !hasStrips(e.monitor)))
                setOpen(e.monitor, false);
            step(*VIEW, e.monitor);
            if (!VIEW->open && VIEW->z <= 0.0) {
                dropView(VIEW); // back at the desktop: this frame is drawn plainly
                g_pInputManager->simulateMouseMovement(); // and the pointer is where it looks again
            }
        } else if (e.stage == RENDER_POST) {
            // Hyprland tells every window of the shown workspace that a frame
            // went out, drawn or not. The other rows get the same: a surface
            // that was drawn has been told already (and has nothing left to
            // be told), but a window of a row out of sight, or in a column
            // past the edge of the screen, would wait for a frame for as
            // long as the view is up.
            const auto NOW = Time::steadyNow();
            for (auto const& ref : VIEW->rows) {
                const auto ws = ref.lock();
                if (ws && ws != e.monitor->m_activeWorkspace)
                    g_pHyprRenderer->sendFrameEventsToWorkspace(e.monitor, ws, NOW);
            }
            if (VIEW->animating)
                g_pHyprRenderer->damageMonitor(e.monitor); // and so the next frame
            else if (VIEW->settled) {
                // The view moved under a pointer that did not: have what is
                // under it now looked up again.
                VIEW->settled = false;
                g_pInputManager->simulateMouseMovement();
            }
        }
    }

    void onButton(const IPointer::SButtonEvent& e) {
        if (e.state == WL_POINTER_BUTTON_STATE_PRESSED) {
            if (g_buttons++ == 0 && g_pointer.zoomed) {
                for (auto const& v : g_views)
                    v->locked = g_pointer.row;
            }
            return;
        }
        g_buttons = std::max(0, g_buttons - 1);
        if (g_buttons == 0) {
            for (auto const& v : g_views) {
                v->locked.reset();
                damage(*v); // the camera may have a focus change to catch up with
            }
        }
    }

    void onMonitorGone(const PHLMONITOR& mon) {
        if (const auto VIEW = viewFor(mon))
            dropView(VIEW);
    }

    // Hyprland 0.57.2 symbols (nm -D). Itanium mangling carries the whole
    // signature, so a match is exactly the overload the hook was written for.
    namespace Symbols {
        constexpr auto RENDER_WINDOWS =
            "_ZN6Render13IHyprRenderer22renderWorkspaceWindowsERNS_14CRenderContextEN9Hyprutils6Memory14CSharedPointerIN7Monitor8CMonitorEEENS5_IN9Workspace12CHLWorkspaceEEERKNSt6"
            "chrono10time_pointINSC_3_V212steady_clockENSC_8durationIlSt5ratioILl1ELl1000000000EEEEEENS_10eSceneModeE";
        constexpr auto RENDER_WINDOWS_FULLSCREEN =
            "_ZN6Render13IHyprRenderer32renderWorkspaceWindowsFullscreenERNS_14CRenderContextEN9Hyprutils6Memory14CSharedPointerIN7Monitor8CMonitorEEENS5_IN9Workspace12CHLWorkspac"
            "eEEERKNSt6chrono10time_pointINSC_3_V212steady_clockENSC_8durationIlSt5ratioILl1ELl1000000000EEEEEENS_10eSceneModeE";
        constexpr auto WINDOW_AT =
            "_ZNK7Desktop14CViewHitTester16windowAtInternalERKN9Hyprutils4Math8Vector2DEtNS1_6Memory14CSharedPointerINS_4View7CWindowEEENS7_IN9Workspace12CHLWorkspaceEEE";
        constexpr auto LAYER_AT =
            "_ZNK7Desktop14CViewHitTester14layerSurfaceAtERKN9Hyprutils4Math8Vector2DEPSt6vectorINS1_6Memory12CWeakPointerINS_4View13CLayerSurfaceEEESaISB_EEPS3_PNS7_14CSharedPoin"
            "terISA_EEb";
        constexpr auto LAYER_POPUP_AT =
            "_ZNK7Desktop14CViewHitTester19layerPopupSurfaceAtERKN9Hyprutils4Math8Vector2DENS1_6Memory14CSharedPointerIN7Monitor8CMonitorEEEPS3_PNS7_INS_4View13CLayerSurfaceEEE";
        constexpr auto FULLSCREEN_WINDOW =
            "_ZN10Fullscreen21CFullscreenController19getFullscreenWindowEN9Hyprutils6Memory14CSharedPointerIN9Workspace12CHLWorkspaceEEESt8optionalIbE";
        constexpr auto MOUSE_MOVE     = "_ZN13CInputManager16mouseMoveUnifiedEjbbSt8optionalIN9Hyprutils4Math8Vector2DEEb";
        constexpr auto TEXTURE_WITH_BLUR =
            "_ZN6Render2GL15CHyprOpenGLImpl29renderTextureWithBlurInternalERNS_14CRenderContextEN9Hyprutils6Memory14CSharedPointerINS_8ITextureEEERKNS4_4Math4CBoxERKNS1_18STextureRenderDataE";
        constexpr auto DAMAGE_SURFACE = "_ZN6Render13IHyprRenderer13damageSurfaceEN9Hyprutils6Memory14CSharedPointerI18CWLSurfaceResourceEEddd";
        constexpr auto DAMAGE_WINDOW  = "_ZN6Render13IHyprRenderer12damageWindowEN9Hyprutils6Memory14CSharedPointerIN7Desktop4View7CWindowEEEb";
        constexpr auto DAMAGE_BOX     = "_ZN6Render13IHyprRenderer9damageBoxERKN9Hyprutils4Math4CBoxEb";
        constexpr auto COMMIT_WINDOW  = "_ZN7Desktop4View7CWindow12commitWindowEb";
        constexpr auto COMMIT_SUB     = "_ZN7Desktop4View11CSubsurface8onCommitEv";
        constexpr auto COMMIT_POPUP   = "_ZN7Desktop4View6CPopup8onCommitEb";
        constexpr auto COMMIT_STATE   = "_ZN18CWLSurfaceResource11commitStateER13SSurfaceState";
    }

    // A function of the Hyprland executable itself, by mangled name. The
    // dladdr check turns down a same-named symbol from any other loaded object.
    void* hyprlandFunction(const char* mangled) {
        Dl_info     hyprland{};
        Dl_info     symbol{};
        void* const ADDRESS = dlsym(RTLD_DEFAULT, mangled);
        if (ADDRESS && dladdr(rc<void*>(&HyprlandAPI::createFunctionHook), &hyprland) && dladdr(ADDRESS, &symbol) && symbol.dli_fbase == hyprland.dli_fbase)
            return ADDRESS;
        return nullptr;
    }

    std::vector<CFunctionHook*> g_hooks;

    CFunctionHook* hook(const char* mangled, void* destination) {
        void* const ADDRESS = hyprlandFunction(mangled);
        if (!ADDRESS)
            return nullptr;
        const auto HOOK = HyprlandAPI::createFunctionHook(PHANDLE, ADDRESS, destination);
        if (!HOOK)
            return nullptr;
        // hook() fails when another plugin owns the address; m_original then stays null.
        if (!HOOK->hook()) {
            HyprlandAPI::removeFunctionHook(PHANDLE, HOOK);
            return nullptr;
        }
        g_hooks.emplace_back(HOOK);
        return HOOK;
    }

    void unhookAll() {
        for (auto const& h : g_hooks)
            HyprlandAPI::removeFunctionHook(PHANDLE, h);
        g_hooks.clear();
        g_hookWindows = g_hookWindowsFullscreen = g_hookWindowAt = g_hookLayerAt = g_hookLayerPopupAt = g_hookDamageSurface = g_hookDamageWindow = g_hookFullscreenWindow = g_hookMouseMove =
            g_hookTextureWithBlur = g_hookDamageBox = g_hookCommitWindow = g_hookCommitSub = g_hookCommitPopup = g_hookCommitState = nullptr;
    }
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    if (std::string{__hyprland_api_get_hash()} != std::string{__hyprland_api_get_client_hash()}) {
        HyprlandAPI::addNotification(PHANDLE, "[stackzoom] built for another Hyprland, not loaded", CHyprColor{1.0, 0.2, 0.2, 1.0}, 6000);
        throw std::runtime_error("[stackzoom] version mismatch");
    }

    g_hookWindows           = hook(Symbols::RENDER_WINDOWS, rc<void*>(&hkRenderWindows));
    g_hookWindowsFullscreen = hook(Symbols::RENDER_WINDOWS_FULLSCREEN, rc<void*>(&hkRenderWindowsFullscreen));
    g_hookWindowAt          = hook(Symbols::WINDOW_AT, rc<void*>(&hkWindowAt));
    g_hookLayerAt           = hook(Symbols::LAYER_AT, rc<void*>(&hkLayerAt));
    g_hookLayerPopupAt      = hook(Symbols::LAYER_POPUP_AT, rc<void*>(&hkLayerPopupAt));
    g_hookFullscreenWindow  = hook(Symbols::FULLSCREEN_WINDOW, rc<void*>(&hkFullscreenWindow));
    g_hookMouseMove         = hook(Symbols::MOUSE_MOVE, rc<void*>(&hkMouseMove));
    g_hookTextureWithBlur   = hook(Symbols::TEXTURE_WITH_BLUR, rc<void*>(&hkTextureWithBlur));
    g_hookDamageSurface     = hook(Symbols::DAMAGE_SURFACE, rc<void*>(&hkDamageSurface));
    g_hookDamageWindow      = hook(Symbols::DAMAGE_WINDOW, rc<void*>(&hkDamageWindow));
    g_hookDamageBox         = hook(Symbols::DAMAGE_BOX, rc<void*>(&hkDamageBox));
    g_hookCommitWindow      = hook(Symbols::COMMIT_WINDOW, rc<void*>(&hkCommitWindow));
    g_hookCommitSub         = hook(Symbols::COMMIT_SUB, rc<void*>(&hkCommitSub));
    g_hookCommitPopup       = hook(Symbols::COMMIT_POPUP, rc<void*>(&hkCommitPopup));
    g_hookCommitState       = hook(Symbols::COMMIT_STATE, rc<void*>(&hkCommitState));

    g_ready = g_hookWindows && g_hookWindowsFullscreen && g_hookWindowAt && g_hookLayerAt && g_hookLayerPopupAt && g_hookFullscreenWindow && g_hookMouseMove && g_hookTextureWithBlur && g_hookDamageSurface &&
        g_hookDamageWindow && g_hookDamageBox && g_hookCommitWindow && g_hookCommitSub && g_hookCommitPopup && g_hookCommitState;
    if (!g_ready) {
        // Half a set of hooks would draw the view without its input, or the other way round.
        unhookAll();
        HyprlandAPI::addNotification(PHANDLE, "[stackzoom] this Hyprland build is not the one it was written for: the view is off", CHyprColor{1.0, 0.8, 0.2, 1.0}, 6000);
    } else {
        g_transformer = makeShared<Pointer::CPointerTransformer>(transformPointer);
        Pointer::mgr()->addTransformer(g_transformer);

        g_listeners.emplace_back(Event::bus()->m_events.render.stage.listen([](const Event::SRenderStageEvent& e) { onRenderStage(e); }));
        g_listeners.emplace_back(Event::bus()->m_events.input.mouse.button.listen([](const IPointer::SButtonEvent& e, Event::SCallbackInfo&) { onButton(e); }));
        g_listeners.emplace_back(Event::bus()->m_events.monitor.removed.listen([](PHLMONITOR mon) { onMonitorGone(mon); }));
        g_listeners.emplace_back(Event::bus()->m_events.monitor.destroyMon.listen([](PHLMONITOR mon) { onMonitorGone(mon); }));
        // Hyprland suspends the windows of the workspace that was left.
        g_listeners.emplace_back(Event::bus()->m_events.workspace.active.listen([](PHLWORKSPACE) {
            for (auto const& v : g_views) {
                if (const auto MON = v->mon.lock())
                    wake(rowsOf(MON));
                damage(*v);
            }
        }));
    }

    // Needs no hook, and is right with or without the view: everything that
    // reads where the windows of another workspace are (ALT + J/K across the
    // strips, the HUD's overview) is told the truth.
    g_listeners.emplace_back(Event::bus()->m_events.workspace.moveToMonitor.listen([](PHLWORKSPACE ws, PHLMONITOR mon) {
        if (!ws || !mon || ws == mon->m_activeWorkspace)
            return;
        settle(ws);
        if (const auto VIEW = viewFor(mon))
            damage(*VIEW);
    }));

    HyprlandAPI::addLuaFunction(PHANDLE, "stackzoom", "toggle", luaToggle);
    HyprlandAPI::addLuaFunction(PHANDLE, "stackzoom", "open", luaOpen);
    HyprlandAPI::addLuaFunction(PHANDLE, "stackzoom", "close", luaClose);
    HyprlandAPI::addLuaFunction(PHANDLE, "stackzoom", "active", luaActive);
    HyprlandAPI::addLuaFunction(PHANDLE, "stackzoom", "probe", luaProbe);
    HyprlandAPI::addLuaFunction(PHANDLE, "stackzoom", "precise", luaPrecise);
    HyprlandAPI::addLuaFunction(PHANDLE, "stackzoom", "stats", luaStats);
    HyprlandAPI::addLuaFunction(PHANDLE, "stackzoom", "centred", luaCentred);
    HyprlandAPI::addLuaFunction(PHANDLE, "stackzoom", "zoom", luaZoom);

    return {"stackzoom", "Zoomed-out work view of a monitor's workspaces, with live windows", "mael", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_ready = false;
    g_listeners.clear();
    while (!g_views.empty())
        dropView(g_views.back().get());
    if (g_transformer) {
        Pointer::mgr()->removeTransformer(g_transformer);
        g_transformer.reset();
    }
    unhookAll();
}
