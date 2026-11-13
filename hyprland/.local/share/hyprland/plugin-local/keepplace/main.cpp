// keepplace: windows keep their place and their size when the layout changes
// between dwindle and the scrolling strip (SUPER + S, bindings.lua).
//
// Hyprland changes a workspace's layout by taking every tiled window out of
// the old one and handing it to the new one as if it had just been opened:
// in the order the windows were first tiled, each placed beside the focused
// window or the one under the pointer, at the default size. So windows that
// had been swapped traded places again, a strip column came back at half a
// screen whatever width it had, and a window that filled the screen became
// one tile among the others.
//
// Here the new layout is built from what is on the screen instead:
//
//   to the strip   columns in the order the tiles lie from left to right,
//                  each as wide as its tile; tiles above each other are one
//                  column. A maximized window is a column the width of the
//                  screen (what ALT + F makes on the strip), and the strip is
//                  slid so that the focused window stays where it is.
//   to dwindle     the columns side by side in the same order and the same
//                  proportions. Where the strip ran off the screen with one
//                  window filling it, that window is maximized over the
//                  others, so it stays as it is.
//
// Dwindle shows every window at once, the strip does not: what a strip held
// off the screen has to come onto it, and the widths give way. They are
// remembered, and come back with the strip as long as the tiles were left
// alone in between.
//
// Any other pair of layouts is left to Hyprland.
//
// Written against Hyprland 0.57.2. The one hooked function is looked up by
// its exact mangled name: on any other build it is not found and the plugin
// does nothing.

#define WLR_USE_UNSTABLE

// The layouts keep their windows to themselves. Whatever their headers
// include comes first, so that only the layouts are opened.
#include <hyprland/src/defines.hpp>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/space/Space.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/workspace/HLWorkspace.hpp>

#include <dlfcn.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <optional>
#include <string>
#include <typeinfo>
#include <vector>

#define private   public
#define protected public
#include <hyprland/src/layout/algorithm/ModeAlgorithm.hpp>
#include <hyprland/src/layout/algorithm/TiledAlgorithm.hpp>
#include <hyprland/src/layout/algorithm/Algorithm.hpp>
#include <hyprland/src/layout/algorithm/tiled/dwindle/DwindleAlgorithm.hpp>
#include <hyprland/src/layout/algorithm/tiled/scrolling/ScrollTapeController.hpp>
#include <hyprland/src/layout/algorithm/tiled/scrolling/ScrollingAlgorithm.hpp>
#undef private
#undef protected

#include <hyprland/src/layout/supplementary/WorkspaceAlgoMatcher.hpp>

namespace {
    using namespace Layout;
    using namespace Layout::Tiled;

    HANDLE         PHANDLE = nullptr;
    CFunctionHook* g_hook  = nullptr;

    constexpr auto UPDATE_TILED_ALGO = "_ZN6Layout10CAlgorithm15updateTiledAlgoEON9Hyprutils6Memory14CUniquePointerINS_15ITiledAlgorithmEEE";

    // Two tiles are in one column, or a tile is where it was left, within this
    // share of the work area (a rounded pixel on a narrow screen is less).
    constexpr double SAME = 0.01;
    // A column this wide fills the screen (the same line bindings.lua draws).
    constexpr double FILLS = 0.9;
    // Dwindle's own limits for a split.
    constexpr float RATIO_MIN = 0.1F, RATIO_MAX = 1.9F;
    // The strip's (MIN_COLUMN_WIDTH, MAX_COLUMN_WIDTH in ScrollingAlgorithm.cpp).
    constexpr double WIDTH_MIN = 0.05, WIDTH_MAX = 1.0;

    // A tile as a share of the work area: independent of the gaps, which
    // change with the layout (motion.lua).
    struct SShare {
        double x = 0, y = 0, w = 1, h = 1;

        bool   near(const SShare& o) const {
            return std::abs(x - o.x) < SAME && std::abs(y - o.y) < SAME && std::abs(w - o.w) < SAME && std::abs(h - o.h) < SAME;
        }
    };

    SShare shareOf(const CBox& box, const CBox& work) {
        return {(box.x - work.x) / work.w, (box.y - work.y) / work.h, box.w / work.w, box.h / work.h};
    }

    struct SMode {
        PHLWINDOW                   window;
        Fullscreen::SFullscreenMode modes;
    };

    struct SColumn {
        double                   width = 0.5; // share of the screen
        double                   x     = 0;   // where it is, as a share of the screen from its left edge
        std::vector<SP<ITarget>> targets;     // top to bottom
        std::vector<double>      heights;     // shares of the column, one per target
    };

    // What a window had on the strip, and the tile dwindle gave it for that.
    struct SMemo {
        PHLWINDOWREF window;
        double       width = 0.5;
        double       x     = 0; // of its column on the strip, from the screen's left edge
        SShare       tile;
    };
    std::vector<SMemo> g_memos;

    SMemo* memoFor(const PHLWINDOW& window) {
        for (auto& m : g_memos) {
            if (m.window.lock() == window)
                return &m;
        }
        return nullptr;
    }

    void forget(const PHLWINDOW& window) {
        std::erase_if(g_memos, [&](const SMemo& m) { return m.window.expired() || m.window.lock() == window; });
    }

    std::vector<double> normalised(std::vector<double> sizes) {
        double total = 0;
        for (auto& s : sizes) {
            s = std::max(s, 0.0);
            total += s;
        }
        for (auto& s : sizes)
            s = total > 0 ? s / total : 1.0 / sizes.size();
        return sizes;
    }

    // --- reading the layout that is left ---

    struct SStripRead {
        std::vector<SColumn> columns;
        // The window that fills the screen with others beside it off the
        // screen, if that is what the strip shows.
        SP<ITarget> filling;
    };

    std::optional<SStripRead> readStrip(CScrollingAlgorithm* strip, const CBox& work, const SP<ITarget>& focused) {
        const auto DATA = strip->m_scrollingData;
        if (!DATA || !DATA->controller || DATA->controller->getDirection() != SCROLL_DIR_RIGHT || DATA->controller->stripCount() != DATA->columns.size())
            return std::nullopt;

        SStripRead read;
        double     total = 0, mostSeen = 0;
        size_t     reference = 0;
        bool       focusedHere = false;

        for (size_t i = 0; i < DATA->columns.size(); ++i) {
            const auto& COL   = DATA->columns[i];
            const auto& STRIP = DATA->controller->getStrip(i);
            if (!COL || COL->targetDatas.empty())
                return std::nullopt;

            SColumn column;
            CBox    box;
            for (size_t j = 0; j < COL->targetDatas.size(); ++j) {
                const auto TARGET = COL->targetDatas[j]->target.lock();
                if (!TARGET)
                    return std::nullopt;
                if (j == 0)
                    box = TARGET->position();
                if (TARGET == focused) {
                    focusedHere = true;
                    reference   = i;
                }
                column.targets.emplace_back(TARGET);
                column.heights.emplace_back(j < STRIP.targetSizes.size() ? STRIP.targetSizes[j] : 1.0);
            }
            // The tile, not the setting: a lone column is the whole screen
            // whatever its width says (scrolling:fullscreen_on_one_column).
            column.width   = std::clamp(box.w / work.w, WIDTH_MIN, WIDTH_MAX);
            column.x       = (box.x - work.x) / work.w;
            column.heights = normalised(column.heights);
            total += column.width;

            const double SEEN = std::min(box.x + box.w, work.x + work.w) - std::max(box.x, work.x);
            if (!focusedHere && SEEN > mostSeen) {
                mostSeen  = SEEN;
                reference = i;
            }
            read.columns.emplace_back(std::move(column));
        }

        if (total > 1.0 + SAME && !read.columns.empty()) {
            const auto& COLUMN = read.columns[reference];
            if (COLUMN.width >= FILLS && COLUMN.targets.size() == 1)
                read.filling = COLUMN.targets[0];
        }
        return read;
    }

    struct STile {
        SP<ITarget> target;
        SShare      share;
        Fullscreen::eFullscreenMode mode = Fullscreen::FSMODE_NONE; // what it had before the change
    };

    std::optional<std::vector<STile>> readDwindle(CDwindleAlgorithm* dwindle, const CBox& work, const std::vector<SMode>& modes) {
        std::vector<STile> tiles;
        for (const auto& node : dwindle->m_dwindleNodesData) {
            if (!node || node->isNode)
                continue;
            const auto TARGET = node->pTarget.lock();
            if (!TARGET || node->box.w <= 0 || node->box.h <= 0)
                return std::nullopt;
            const auto MODE = std::ranges::find_if(modes, [&](const SMode& m) { return m.window == TARGET->window(); });
            tiles.emplace_back(STile{TARGET, shareOf(node->box, work), MODE == modes.end() ? Fullscreen::FSMODE_NONE : MODE->modes.internal});
        }
        return tiles;
    }

    // --- building the layout that comes ---

    struct SStripPlan {
        std::vector<SColumn> columns;
        double               offset = 0; // of the strip, in shares of the screen
        SP<ITarget>          focused;    // kept in sight, wherever the offset puts it
    };

    SStripPlan planStrip(std::vector<STile> tiles, const SP<ITarget>& focused) {
        std::ranges::stable_sort(tiles, [](const STile& a, const STile& b) {
            if (std::abs(a.share.x - b.share.x) >= SAME)
                return a.share.x < b.share.x;
            return a.share.y < b.share.y;
        });

        // What the window had on the strip, while its tile is still the one
        // dwindle gave it for that.
        const auto KEPT = [](const STile& tile) -> const SMemo* {
            const auto MEMO = tile.target->window() ? memoFor(tile.target->window()) : nullptr;
            return MEMO && MEMO->tile.near(tile.share) ? MEMO : nullptr;
        };
        // No tile was touched since the strip was left: it comes back as it
        // was. Otherwise the strip is what dwindle shows, tile for tile; a
        // mix of the two would be neither.
        const bool UNTOUCHED = !tiles.empty() && std::ranges::all_of(tiles, [&](const STile& tile) { return KEPT(tile) != nullptr; });
        const auto WIDTH     = [&](const STile& tile) {
            // Maximized is a column the width of the screen here (ALT + F).
            // Fullscreen is put back on the window, over the column it has.
            if (tile.mode == Fullscreen::FSMODE_MAXIMIZED)
                return WIDTH_MAX;
            return std::clamp(UNTOUCHED ? KEPT(tile)->width : tile.share.w, WIDTH_MIN, WIDTH_MAX);
        };

        SStripPlan            plan;
        plan.focused = focused;
        std::vector<SShare>   first; // the first tile of each column
        std::vector<bool>     alone; // a maximized or fullscreen window shares its column with nobody
        const STile*          reference = nullptr;
        size_t                referenceColumn = 0;

        for (const auto& tile : tiles) {
            const bool COVERS = tile.mode != Fullscreen::FSMODE_NONE;
            const bool JOINS  = !plan.columns.empty() && !COVERS && !alone.back() && std::abs(first.back().x - tile.share.x) < SAME && std::abs(first.back().w - tile.share.w) < SAME &&
                std::abs(plan.columns.back().width - WIDTH(tile)) < SAME;
            if (JOINS) {
                plan.columns.back().targets.emplace_back(tile.target);
                plan.columns.back().heights.emplace_back(tile.share.h);
            } else {
                plan.columns.emplace_back(SColumn{WIDTH(tile), 0.0, {tile.target}, {tile.share.h}});
                first.emplace_back(tile.share);
                alone.emplace_back(COVERS);
            }
            // Whoever is looked at stays put: the focused window, else one that covers the rest.
            if (tile.target == focused || (COVERS && (!reference || reference->target != focused))) {
                reference       = &tile;
                referenceColumn = plan.columns.size() - 1;
            }
        }

        double total = 0, before = 0;
        for (size_t i = 0; i < plan.columns.size(); ++i) {
            plan.columns[i].heights = normalised(plan.columns[i].heights);
            if (i < referenceColumn)
                before += plan.columns[i].width;
            total += plan.columns[i].width;
        }
        if (reference && reference->mode != Fullscreen::FSMODE_NONE)
            plan.offset = before;
        else if (UNTOUCHED)
            plan.offset = -KEPT(tiles.front())->x;
        else if (reference)
            plan.offset = before - reference->share.x;
        if (plan.columns.empty())
            return plan;
        // As far as the strip goes by itself: its last column at the left
        // edge, with the screen empty beside it.
        plan.offset = std::clamp(plan.offset, 0.0, std::max(total - plan.columns.back().width, 0.0));
        return plan;
    }

    void buildStrip(CScrollingAlgorithm* strip, const SStripPlan& plan, const CBox& work) {
        const auto DATA = strip->m_scrollingData;
        for (const auto& column : plan.columns) {
            const auto COL = DATA->add(std::optional<float>(sc<float>(column.width)));
            for (const auto& target : column.targets)
                COL->add(target);
            for (size_t j = 0; j < column.targets.size(); ++j)
                COL->setTargetSize(j, sc<float>(column.heights[j]));
        }
        DATA->controller->setOffset(std::round(plan.offset * work.w));
        // No further than it takes, and not at all if the window is in sight.
        if (const auto FOCUSED = plan.focused ? strip->dataFor(plan.focused) : nullptr)
            DATA->fitCol(FOCUSED->column.lock());
        DATA->recalculate();
    }

    void buildDwindle(CDwindleAlgorithm* dwindle, const std::vector<SColumn>& columns) {
        auto&      nodes = dwindle->m_dwindleNodesData;

        const auto LEAF = [&](const SP<ITarget>& target) {
            const auto NODE = nodes.emplace_back(makeShared<SDwindleNodeData>());
            NODE->self      = NODE;
            NODE->pTarget   = target;
            return NODE;
        };
        // The items one after the other, each split off from what follows it.
        // The direction of a split holds only with dwindle:preserve_split
        // (looknfeel.lua); without it dwindle picks it from the tile's shape.
        const auto CHAIN = [&](const std::vector<SP<SDwindleNodeData>>& items, const std::vector<double>& sizes, bool top) {
            auto   node = items.back();
            double rest = sizes.back();
            for (size_t i = items.size() - 1; i-- > 0;) {
                rest += sizes[i];
                const auto PARENT   = nodes.emplace_back(makeShared<SDwindleNodeData>());
                PARENT->self        = PARENT;
                PARENT->isNode      = true;
                PARENT->splitTop    = top;
                PARENT->splitRatio  = std::clamp(sc<float>(rest > 0 ? 2.0 * sizes[i] / rest : 1.0), RATIO_MIN, RATIO_MAX);
                PARENT->children    = {items[i], node};
                items[i]->pParent   = PARENT;
                node->pParent       = PARENT;
                node                = PARENT;
            }
            return node;
        };

        std::vector<SP<SDwindleNodeData>> stacks;
        std::vector<double>               widths;
        for (const auto& column : columns) {
            std::vector<SP<SDwindleNodeData>> leaves;
            for (const auto& target : column.targets)
                leaves.emplace_back(LEAF(target));
            stacks.emplace_back(CHAIN(leaves, column.heights, true));
            widths.emplace_back(column.width);
        }
        if (!stacks.empty())
            CHAIN(stacks, widths, false);

        dwindle->recalculate();
    }

    // --- the change itself ---

    using origUpdate = void (*)(CAlgorithm*, UP<ITiledAlgorithm>*);

    void hkUpdateTiledAlgo(CAlgorithm* self, UP<ITiledAlgorithm>* incoming) {
        const auto ORIGINAL = [&] { rc<origUpdate>(g_hook->m_original)(self, incoming); };

        const auto SPACE = self->m_space.lock();
        if (!incoming || !*incoming || !self->m_tiled || !SPACE || !SPACE->workspace() || !SPACE->workspace()->m_monitor || self->m_tiledTargets.empty())
            return ORIGINAL();

        const CBox WORK = SPACE->workArea();
        if (WORK.w <= 1 || WORK.h <= 1)
            return ORIGINAL();

        const auto& MATCHER = Supplementary::algoMatcher();
        const auto  FROM    = MATCHER->getNameForTiledAlgo(self->m_tiled.get());
        const auto  TO      = MATCHER->getNameForTiledAlgo(incoming->get());
        const bool  TO_STRIP   = FROM == "dwindle" && TO == "scrolling";
        const bool  TO_DWINDLE = FROM == "scrolling" && TO == "dwindle";
        if (!TO_STRIP && !TO_DWINDLE)
            return ORIGINAL();
        // By type as well: a layout may give itself any name, and what
        // follows reaches into these two classes.
        const auto& OLD = *self->m_tiled;
        const auto& NEW = **incoming;
        if (typeid(OLD) != (TO_STRIP ? typeid(CDwindleAlgorithm) : typeid(CScrollingAlgorithm)) || typeid(NEW) != (TO_STRIP ? typeid(CScrollingAlgorithm) : typeid(CDwindleAlgorithm)))
            return ORIGINAL();

        const auto FOCUSED_WINDOW = Desktop::focusState()->window();
        const auto FOCUSED_TARGET = FOCUSED_WINDOW ? FOCUSED_WINDOW->layoutTarget() : nullptr;
        const auto FOCUSED_HERE   = FOCUSED_TARGET && FOCUSED_TARGET->space() == SPACE && !FOCUSED_TARGET->floating() ? FOCUSED_TARGET : nullptr;

        std::vector<SP<ITarget>> targets;
        for (const auto& t : self->m_tiledTargets) {
            if (const auto TARGET = t.lock())
                targets.emplace_back(TARGET);
        }
        if (targets.empty())
            return ORIGINAL();

        // Taking a window out of a layout ends its fullscreen. Ended here
        // already: the strip then shows the column the window has under it.
        std::vector<SMode> modes;
        for (const auto& target : targets) {
            const auto WINDOW = target->window();
            if (!WINDOW)
                continue;
            if (const auto MODES = Fullscreen::controller()->getFullscreenModes(WINDOW); MODES.internal != Fullscreen::FSMODE_NONE)
                modes.emplace_back(SMode{WINDOW, MODES});
        }
        for (const auto& mode : modes)
            Fullscreen::controller()->setFullscreenMode(mode.window, Fullscreen::FSMODE_NONE);

        // Read what is there before anything is taken out of it.
        std::optional<SStripRead> strip;
        std::optional<SStripPlan> plan;
        if (TO_DWINDLE)
            strip = readStrip(sc<CScrollingAlgorithm*>(self->m_tiled.get()), WORK, FOCUSED_HERE);
        else if (auto tiles = readDwindle(sc<CDwindleAlgorithm*>(self->m_tiled.get()), WORK, modes))
            plan = planStrip(std::move(*tiles), FOCUSED_HERE);

        // Every window must have its place in the plan, and once, or Hyprland places them.
        if (TO_DWINDLE ? !strip : !plan)
            return ORIGINAL();
        std::vector<SP<ITarget>> planned;
        for (const auto& column : TO_DWINDLE ? strip->columns : plan->columns)
            planned.insert(planned.end(), column.targets.begin(), column.targets.end());
        if (planned.size() != targets.size() || !std::ranges::all_of(targets, [&](const SP<ITarget>& t) { return std::ranges::count(planned, t) == 1; }))
            return ORIGINAL();

        auto& algo     = *incoming;
        algo->m_parent = self->m_self;
        if (TO_STRIP && sc<CScrollingAlgorithm*>(algo.get())->getDynamicDirection() != SCROLL_DIR_RIGHT)
            return ORIGINAL();

        for (const auto& target : targets) {
            // As Hyprland does: nothing a layout has hidden may stay lost.
            if (const auto WINDOW = target->window())
                WINDOW->setHidden(false);
            self->m_tiled->removeTarget(target);
        }

        if (TO_STRIP)
            buildStrip(sc<CScrollingAlgorithm*>(algo.get()), *plan, WORK);
        else
            buildDwindle(sc<CDwindleAlgorithm*>(algo.get()), strip->columns);

        if (FOCUSED_HERE)
            Desktop::focusState()->fullWindowFocus(FOCUSED_WINDOW, Desktop::eFocusReason::FOCUS_REASON_DESKTOP_STATE_CHANGE);

        self->m_tiled = std::move(algo);

        if (TO_DWINDLE) {
            // The widths the strip had, for the way back.
            const auto DWINDLE = sc<CDwindleAlgorithm*>(self->m_tiled.get());
            for (const auto& column : strip->columns) {
                for (const auto& target : column.targets) {
                    const auto WINDOW = target->window();
                    const auto NODE   = DWINDLE->getNodeFromTarget(target);
                    if (!WINDOW)
                        continue;
                    forget(WINDOW);
                    // No tile yet under a fullscreen window that is not the
                    // layout's (dwindle leaves the workspace alone then).
                    if (!NODE || NODE->box.w <= 0 || NODE->box.h <= 0)
                        continue;
                    g_memos.emplace_back(SMemo{WINDOW, column.width, column.x, shareOf(NODE->box, WORK)});
                }
            }
        } else {
            for (const auto& target : targets) {
                if (target->window())
                    forget(target->window());
            }
        }

        // Fullscreen stays fullscreen. Maximized is a column of the strip's
        // own there; in dwindle it is how a screen-filling window stays so.
        PHLWINDOW covering;
        for (const auto& mode : modes) {
            if (mode.modes.internal == Fullscreen::FSMODE_FULLSCREEN) {
                Fullscreen::controller()->setFullscreenMode(mode.window, mode.modes.internal, mode.modes.client);
                covering = mode.window;
            } else if (TO_DWINDLE && !covering) {
                Fullscreen::controller()->setFullscreenMode(mode.window, Fullscreen::FSMODE_MAXIMIZED);
                covering = mode.window;
            }
        }
        if (TO_DWINDLE && !covering && strip->filling && strip->filling->window())
            Fullscreen::controller()->setFullscreenMode(strip->filling->window(), Fullscreen::FSMODE_MAXIMIZED);
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
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    if (std::string{__hyprland_api_get_hash()} != std::string{__hyprland_api_get_client_hash()}) {
        HyprlandAPI::addNotification(PHANDLE, "[keepplace] built for another Hyprland, not loaded", CHyprColor{1.0, 0.2, 0.2, 1.0}, 6000);
        throw std::runtime_error("[keepplace] version mismatch");
    }

    if (void* const ADDRESS = hyprlandFunction(UPDATE_TILED_ALGO)) {
        g_hook = HyprlandAPI::createFunctionHook(PHANDLE, ADDRESS, rc<void*>(&hkUpdateTiledAlgo));
        // hook() fails when another plugin owns the address.
        if (g_hook && !g_hook->hook()) {
            HyprlandAPI::removeFunctionHook(PHANDLE, g_hook);
            g_hook = nullptr;
        }
    }
    if (!g_hook)
        HyprlandAPI::addNotification(PHANDLE, "[keepplace] this Hyprland build is not the one it was written for: layout changes are Hyprland's own", CHyprColor{1.0, 0.8, 0.2, 1.0}, 6000);

    return {"keepplace", "Windows keep their place and size across a change of layout", "mael", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    if (g_hook)
        HyprlandAPI::removeFunctionHook(PHANDLE, g_hook);
    g_hook = nullptr;
    g_memos.clear();
}
