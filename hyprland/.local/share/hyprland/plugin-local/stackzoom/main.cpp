// stackzoom: the zoomed-out work view of a monitor's workspaces (ALT + Tab,
// bindings.lua).
//
// Every workspace of the monitor that has windows is a row, and the view
// draws back until about two of them fit on the screen. The rows lie the way
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
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
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
#include <string>
#include <vector>

namespace {

    HANDLE PHANDLE = nullptr;

    // How far the view draws back: windows are shown at this share of their size.
    constexpr double ZOOM = 0.5;
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

    // One zoomed monitor.
    struct SView {
        PHLMONITORREF   mon;
        bool            open = false;
        double          z = 0, zFrom = 0, zTo = 0; // 0 = the desktop as it is, 1 = drawn back
        steady_tp       zStart;
        Vector2D        cam, vel, target; // world coordinates, logical pixels
        bool            camSet    = false;
        bool            animating = false;
        bool            settled   = false; // came to rest in this frame
        steady_tp       last;
        bool            lastSet = false;
        PHLWORKSPACEREF locked; // the row the pointer stays in while a button is held
        std::vector<PHLWORKSPACEREF> forced; // workspaces told to draw though not shown
        std::vector<SStrip>          strips;
        std::vector<PHLLSREF>        hud; // desktop HUD layers the view faded out
        bool                         undimmed = false; // the rows' windows have their dim taken off
    };

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
        g.s            = 1.0 + (ZOOM - 1.0) * v.z;
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
    // or down that the screen shows less of the rows than it could.
    Vector2D cameraTarget(const SView& v, const std::vector<PHLWORKSPACE>& rows, const SGeom& g) {
        Vector2D   to      = restCam(g);
        const auto FOCUSED = Desktop::focusState()->window();
        if (FOCUSED && FOCUSED->mapped() && FOCUSED->m_workspace) {
            const int ROW = rowIndex(rows, FOCUSED->m_workspace);
            if (ROW >= 0) {
                const auto POS  = FOCUSED->position(Desktop::View::IGeometric::GEOMETRIC_GOAL) - g.pos;
                const auto SIZE = FOCUSED->size(Desktop::View::IGeometric::GEOMETRIC_GOAL);
                to              = {POS.x + SIZE.x / 2.0 + restOf(v, rows[ROW]), ROW * g.P + (POS.y - g.top) + SIZE.y / 2.0};
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
        const double ACROSS = g.W / ZOOM; // world width the screen shows
        const double REACH  = std::max(0.0, (widest + 2.0 * EDGE - ACROSS) / 2.0);
        to.x                = std::clamp(to.x, g.W / 2.0 - REACH, g.W / 2.0 + REACH);

        const double SPAN = g.n * g.P - ROW_GAP;   // all the rows
        const double SEEN = g.Hu / ZOOM;           // world height the screen shows
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
            if (w->presentation().dimPercent() != 0.F)
                w->presentation().warpDimPercent(0.F);
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

        const auto ROWS = rowsOf(mon);
        for (auto const& ws : ROWS) {
            if (ws->m_forceRendering)
                continue;
            ws->m_forceRendering = true;
            v.forced.emplace_back(ws);
        }

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
        v.animating    = ZOOMING || moving || EASING;
        v.settled      = WAS && !v.animating;
    }

    // ── Rendering ────────────────────────────────────────────────────────────

    // The pass culls what an opaque window covers and what lies off the
    // monitor, both judged where the windows really are, not where the view
    // draws them. This element turns that off for the frame and has it drawn
    // in full.
    class CZoomMarker : public IPassElement {
      public:
        std::vector<UP<IPassElement>> draw(Render::CRenderContext&) override {
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
            return true;
        }
    };

    // Everything in a pass is drawn through the frame's damage, cut to the
    // element's box where the window really is and only then moved by the
    // modifiers: nothing at all for a column that is off the monitor, half of
    // one that is half off it. This element stands before the windows of a
    // row and, when the pass reaches it, widens the damage of every element
    // up to the row's end to the whole plane, so each is cut to its own box
    // and nothing else. What is damaged on the output is not touched.
    class CZoomRow : public IPassElement {
      public:
        explicit CZoomRow(bool begin) : m_begin(begin) {}

        std::vector<UP<IPassElement>> draw(Render::CRenderContext& ctx) override {
            if (!m_begin)
                return {};

            static const CRegion PLANE{CBox{-100000, -100000, 200000, 200000}};
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
                    it->elementDamage = PLANE;
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
        bool m_begin;
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

        const auto ROWS = rowsOf(mon);
        if (ROWS.empty())
            return false;
        const auto   G     = geomOf(*VIEW, mon, ROWS);
        const double SCALE = mon->m_scale;

        Render::IHyprRenderer::addPassElement(ctx, makeUnique<CZoomMarker>());

        CRectPassElement::SRectData shade;
        shade.box   = {0, 0, mon->m_transformedSize.x, mon->m_transformedSize.y};
        shade.color = CHyprColor(0, 0, 0, DIM * VIEW->z);
        Render::IHyprRenderer::addPassElement(ctx, makeUnique<CRectPassElement>(shade));

        for (int r = 0; r < G.n; ++r) {
            // Where the row's top-left corner (its monitor origin) lands on the screen.
            const Vector2D O  = G.pitch * r + Vector2D{G.shift[r], 0.0};
            const Vector2D AT = {G.C.x + (O.x - G.cam.x) * G.s, G.C.y + (O.y - G.top - G.cam.y) * G.s};
            if (AT.y + (G.top + G.Hu) * G.s < 0 || AT.y + G.top * G.s > G.H)
                continue; // wholly above or below the screen

            Render::SRenderModifData modif;
            modif.modifs.emplace_back(Render::SRenderModifData::RMOD_TYPE_SCALE, sc<float>(G.s));
            modif.modifs.emplace_back(Render::SRenderModifData::RMOD_TYPE_TRANSLATE, Vector2D{AT.x * SCALE, AT.y * SCALE});
            Render::IHyprRenderer::addPassElement(ctx, makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{modif}));
            Render::IHyprRenderer::addPassElement(ctx, makeUnique<CZoomRow>(true));

            // The scene of one workspace: its windows wherever they are laid
            // out, whether or not the workspace is the one shown.
            callWindows(Fullscreen::controller()->hasFullscreen(ROWS[r]), self, ctx, mon, ROWS[r], now, Render::eSceneMode::WORKSPACE_WINDOWS);

            Render::IHyprRenderer::addPassElement(ctx, makeUnique<CZoomRow>(false));
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

        const auto SAVED = modif;
        modif            = {};
        (*rc<tTextureWithBlur>(g_hookTextureWithBlur->m_original))(self, ctx, tex, drawn, scaled);
        modif = SAVED;
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

            const auto ROWS = rowsOf(MON);
            if (ROWS.empty())
                return m;
            const auto     G     = geomOf(*v, MON, ROWS);
            const Vector2D WORLD = (raw - G.pos - G.C) / G.s + G.cam;

            m.zoomed = true;
            m.mon    = MON;

            int        row    = -1;
            const auto LOCKED = v->locked.lock();
            if (LOCKED)
                row = rowIndex(ROWS, LOCKED);
            if (row < 0) {
                const int AT = sc<int>(std::floor(WORLD.y / G.P));
                if (AT >= 0 && AT < G.n && WORLD.y - AT * G.P < G.Hu)
                    row = AT;
            }
            if (row < 0)
                return m; // between the rows or past them: no window there

            m.row = ROWS[row];
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
    // is off the monitor or on a workspace not shown. In the view every such
    // window is in sight somewhere else: any change redraws the monitor.
    using tDamageSurface = void (*)(void*, SP<CWLSurfaceResource>, double, double, double);
    using tDamageWindow  = void (*)(void*, PHLWINDOW, bool);

    CFunctionHook* g_hookDamageSurface = nullptr;
    CFunctionHook* g_hookDamageWindow  = nullptr;

    // The views a change to this window can be seen in: its monitor's, or all
    // of them when it is not known whose surface changed.
    void damageViews(const PHLWINDOW& window) {
        const auto MON = window ? window->m_monitor.lock() : nullptr;
        for (auto const& v : g_views) {
            if (!MON || v->mon.lock() == MON)
                damage(*v);
        }
    }

    void hkDamageSurface(void* self, SP<CWLSurfaceResource> surface, double x, double y, double scale) {
        (*rc<tDamageSurface>(g_hookDamageSurface->m_original))(self, surface, x, y, scale);
        if (g_views.empty())
            return;
        const auto HLSURFACE = surface ? Desktop::View::CWLSurface::fromResource(surface) : nullptr;
        damageViews(HLSURFACE ? Desktop::View::CWindow::fromView(HLSURFACE->view()) : nullptr);
    }

    void hkDamageWindow(void* self, PHLWINDOW window, bool forceFull) {
        (*rc<tDamageWindow>(g_hookDamageWindow->m_original))(self, window, forceFull);
        if (!g_views.empty())
            damageViews(window);
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
            view      = g_views.emplace_back(makeUnique<SView>()).get();
            view->mon = mon;
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
            // Hyprland tells only the windows of the shown workspace that a
            // frame went out. The other rows are in sight too: without it
            // their clients never draw again, and a window that was resized
            // (its neighbour taken away, say) keeps its old picture.
            const auto NOW = Time::steadyNow();
            for (auto const& ws : rowsOf(e.monitor)) {
                if (ws != e.monitor->m_activeWorkspace)
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
            g_hookTextureWithBlur = nullptr;
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

    g_ready = g_hookWindows && g_hookWindowsFullscreen && g_hookWindowAt && g_hookLayerAt && g_hookLayerPopupAt && g_hookFullscreenWindow && g_hookMouseMove && g_hookTextureWithBlur && g_hookDamageSurface &&
        g_hookDamageWindow;
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

    HyprlandAPI::addLuaFunction(PHANDLE, "stackzoom", "toggle", luaToggle);
    HyprlandAPI::addLuaFunction(PHANDLE, "stackzoom", "open", luaOpen);
    HyprlandAPI::addLuaFunction(PHANDLE, "stackzoom", "close", luaClose);
    HyprlandAPI::addLuaFunction(PHANDLE, "stackzoom", "active", luaActive);
    HyprlandAPI::addLuaFunction(PHANDLE, "stackzoom", "probe", luaProbe);

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
