/* SPDX-License-Identifier: GPL-3.0-or-later */
#define G_LOG_DOMAIN "kos-gtk-controls"
#include <gtk/gtk.h>
#include <gdk/gdkwayland.h>
#include <gdk/gdkx.h>
#include <wayland-client.h>
#include <string.h>
#include "controls-client.h"

/* Inspect actual GtkHeaderBar title buttons, never application names. A module
 * declaration requests client drawing; it never transfers input to KWin. */
#define STATE_KEY "kos-native-window-controls"
#define X_PROPERTY "_KOS_GTK_NATIVE_CONTROLS_V1"
typedef struct {
    struct kos_window_controls_v1 *controls;
    GdkWindow *surface;
    gboolean native;
} WindowState;
static struct wl_registry *registry;
static struct kos_window_controls_manager_v1 *manager;
static uint32_t manager_name;
static guint idle;
static void schedule(void);
static void header_changed(GObject *object, GParamSpec *pspec, gpointer data) { schedule(); }

static void configured(void *data, struct kos_window_controls_v1 *controls,
                       uint32_t serial, uint32_t active, uint32_t glyph) {
    GtkWidget *window = data;
    kos_window_controls_v1_ack_configure(controls, serial);
    gtk_widget_queue_draw(window);
}
static const struct kos_window_controls_v1_listener listener = { configured };

static void collect(GtkWidget *child, gpointer list) {
    *(GList **)list = g_list_prepend(*(GList **)list, child);
}
/* Same 14 px geometry, colors and glyph proportions as KOS::drawLight.
 * GTK retains its native buttons, accessibility and click handlers. */
static gboolean draw_native_button(GtkWidget *button, cairo_t *cr, gpointer unused) {
    GtkStyleContext *style = gtk_widget_get_style_context(button);
    GdkRGBA enabled, glyph_mode;
    if (!gtk_style_context_lookup_color(style, "kos_native_controls", &enabled)) return FALSE;
    const gboolean close = gtk_style_context_has_class(style, "close");
    const gboolean minimize = gtk_style_context_has_class(style, "minimize");
    if (!close && !minimize && !gtk_style_context_has_class(style, "maximize")) return FALSE;
    GtkWidget *window = gtk_widget_get_toplevel(button);
    const gboolean active = GTK_IS_WINDOW(window) && gtk_window_is_active(GTK_WINDOW(window)) && gtk_widget_is_sensitive(button);
    const gboolean maximized = GTK_IS_WINDOW(window) && gtk_window_is_maximized(GTK_WINDOW(window));
    GtkStateFlags flags = gtk_widget_get_state_flags(button);
    const gboolean hover = flags & GTK_STATE_FLAG_PRELIGHT;
    const guint colors[] = {0xff5f57, 0xfebc2e, 0x28c840};
    const guint borders[] = {0xe0443e, 0xdea123, 0x1aab29};
    const int type = close ? 0 : minimize ? 1 : 2;
    guint fill = active ? colors[type] : 0x9a9a9e;
    guint border = active ? borders[type] : 0x828286;
    const double opacity = flags & GTK_STATE_FLAG_ACTIVE ? .8 : 1.;
    cairo_save(cr);
    cairo_translate(cr, gtk_widget_get_allocated_width(button)/2. - 7., gtk_widget_get_allocated_height(button)/2. - 7.);
    if (hover) {
        GdkRGBA background = {1, 1, 1, 1};
        guint ring = borders[type];
        double alpha = (type == 1 ? 160. : 144.)/255.;
        /* Transparent button backgrounds inherit the header's palette. */
        GtkWidget *bar = gtk_widget_get_ancestor(button, GTK_TYPE_HEADER_BAR);
        if (bar) gtk_style_context_lookup_color(gtk_widget_get_style_context(bar), "theme_bg_color", &background);
        if (background.alpha > 0 && (background.red + background.green + background.blue)/3. < .5) { ring = 0xffffff; alpha = 112./255.; }
        cairo_set_source_rgba(cr, ((ring>>16)&255)/255., ((ring>>8)&255)/255., (ring&255)/255., alpha*opacity);
        cairo_set_line_width(cr, 1.2);
        cairo_arc(cr, 7, 7, 8.5, 0, 2*G_PI); cairo_stroke(cr);
        cairo_set_source_rgba(cr, ((ring>>16)&255)/255., ((ring>>8)&255)/255., (ring&255)/255., alpha*opacity/3.);
        cairo_set_line_width(cr, .6);
        cairo_arc(cr, 7, 7, 8.85, 0, 2*G_PI); cairo_stroke(cr);
        cairo_arc(cr, 7, 7, 8.15, 0, 2*G_PI); cairo_stroke(cr);
    }
    cairo_arc(cr, 7, 7, 7, 0, 2*G_PI);
    cairo_set_source_rgba(cr, ((fill>>16)&255)/255., ((fill>>8)&255)/255., (fill&255)/255., opacity);
    cairo_fill_preserve(cr);
    cairo_set_source_rgba(cr, ((border>>16)&255)/255., ((border>>8)&255)/255., (border&255)/255., opacity);
    cairo_set_line_width(cr, .75); cairo_stroke(cr);
    gboolean glyph = !gtk_style_context_lookup_color(style, "kos_native_glyph", &glyph_mode) || glyph_mode.alpha > .5 || hover;
    if (glyph) {
        double inset = 14 * (type == 2 ? (maximized ? .095 : .23) : .28);
        double lo = inset, hi = 14-inset, side = hi-lo;
        cairo_set_source_rgba(cr, 0, 0, 0, (type == 2 ? 192. : 160.)/255.*opacity);
        cairo_set_line_width(cr, 14*.16); cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
        if (close) {
            cairo_move_to(cr, lo, lo); cairo_line_to(cr, hi, hi);
            cairo_move_to(cr, hi, lo); cairo_line_to(cr, lo, hi); cairo_stroke(cr);
        } else if (minimize) {
            cairo_move_to(cr, lo, 7); cairo_line_to(cr, hi, 7); cairo_stroke(cr);
        } else {
            double ax = side*(maximized ? .48 : .72), ay = side*(maximized ? .46 : .72);
            if (maximized) {
                cairo_move_to(cr, lo+ax, lo); cairo_line_to(cr, lo, lo+ay); cairo_line_to(cr, lo+ax, lo+ay); cairo_close_path(cr);
                cairo_move_to(cr, hi-ax, hi); cairo_line_to(cr, hi, hi-ay); cairo_line_to(cr, hi-ax, hi-ay); cairo_close_path(cr);
            } else {
                cairo_move_to(cr, lo, lo); cairo_line_to(cr, lo+ax, lo); cairo_line_to(cr, lo, lo+ay); cairo_close_path(cr);
                cairo_move_to(cr, hi, hi); cairo_line_to(cr, hi-ax, hi); cairo_line_to(cr, hi, hi-ay); cairo_close_path(cr);
            }
            cairo_fill(cr);
        }
    }
    cairo_restore(cr);
    return TRUE;
}
static void style_control_box(GtkWidget *box, gpointer unused) {
    GdkRGBA enabled;
    const gboolean styled = gtk_style_context_lookup_color(gtk_widget_get_style_context(box), "kos_native_controls", &enabled);
    gpointer saved = g_object_get_data(G_OBJECT(box), "kos-original-spacing");
    if (!saved) {
        if (!styled) return;
        saved = GINT_TO_POINTER(gtk_box_get_spacing(GTK_BOX(box)) + 1);
        g_object_set_data(G_OBJECT(box), "kos-original-spacing", saved);
    }
    gtk_box_set_spacing(GTK_BOX(box), styled ? 0 : GPOINTER_TO_INT(saved)-1);
}
static void style_buttons(GtkWidget *widget) {
    GtkStyleContext *style = gtk_widget_get_style_context(widget);
    if (GTK_IS_BUTTON(widget) && gtk_style_context_has_class(style, "titlebutton")
        && !g_object_get_data(G_OBJECT(widget), "kos-native-draw")) {
        g_object_set_data(G_OBJECT(widget), "kos-native-draw", GINT_TO_POINTER(1));
        g_signal_connect(widget, "draw", G_CALLBACK(draw_native_button), NULL);
        GtkWidget *box = gtk_widget_get_parent(widget);
        if (GTK_IS_BOX(box) && !g_object_get_data(G_OBJECT(box), "kos-spacing-watched")) {
            g_object_set_data(G_OBJECT(box), "kos-spacing-watched", GINT_TO_POINTER(1));
            g_signal_connect(box, "style-updated", G_CALLBACK(style_control_box), NULL);
            style_control_box(box, NULL);
        }
        gtk_widget_queue_draw(widget);
    }
    if (GTK_IS_CONTAINER(widget)) {
        GList *children = NULL;
        gtk_container_forall(GTK_CONTAINER(widget), collect, &children);
        for (GList *it = children; it; it = it->next) style_buttons(it->data);
        g_list_free(children);
    }
}

static gboolean has_close(GtkWidget *widget) {
    if (!gtk_widget_get_visible(widget) || !gtk_widget_get_child_visible(widget)) return FALSE;
    GtkStyleContext *style = gtk_widget_get_style_context(widget);
    if (GTK_IS_BUTTON(widget) && gtk_style_context_has_class(style, "titlebutton")
        && gtk_style_context_has_class(style, "close")) return TRUE;
    if (!GTK_IS_CONTAINER(widget)) return FALSE;
    GList *children = NULL;
    /* forall includes GTK's internal title buttons, unlike get_children. */
    gtk_container_forall(GTK_CONTAINER(widget), collect, &children);
    gboolean found = FALSE;
    for (GList *it = children; it && !found; it = it->next) found = has_close(it->data);
    g_list_free(children);
    return found;
}
static void release(WindowState *state) {
    if (state->controls) kos_window_controls_v1_destroy(state->controls);
    state->controls = NULL;
    if (state->surface && GDK_IS_X11_WINDOW(state->surface) && !gdk_window_is_destroyed(state->surface))
        gdk_property_delete(state->surface, gdk_atom_intern_static_string(X_PROPERTY));
    g_clear_object(&state->surface);
    state->native = FALSE;
}
static void free_state(gpointer data) { WindowState *state = data; release(state); g_free(state); }
static gboolean inspect(gpointer unused) {
    idle = 0;
    GList *windows = gtk_window_list_toplevels();
    for (GList *it = windows; it; it = it->next) {
        GtkWidget *window = it->data;
        WindowState *state = g_object_get_data(G_OBJECT(window), STATE_KEY);
        GtkWidget *bar = gtk_window_get_titlebar(GTK_WINDOW(window));
        GdkWindow *surface = gtk_widget_get_window(window);
        if (bar && GTK_IS_HEADER_BAR(bar) && !g_object_get_data(G_OBJECT(bar), "kos-controls-watched")) {
            g_object_set_data(G_OBJECT(bar), "kos-controls-watched", GINT_TO_POINTER(1));
            g_signal_connect(bar, "notify::show-close-button", G_CALLBACK(header_changed), NULL);
            g_signal_connect(bar, "notify::decoration-layout", G_CALLBACK(header_changed), NULL);
        }
        gboolean native = gtk_widget_get_mapped(window) && surface && bar
            && GTK_IS_HEADER_BAR(bar) && gtk_header_bar_get_show_close_button(GTK_HEADER_BAR(bar))
            && gtk_widget_get_mapped(bar) && has_close(bar);
        g_debug("window header=%s native=%d", bar ? G_OBJECT_TYPE_NAME(bar) : "none", native);
        if (!state && !native) continue;
        if (!state) {
            state = g_new0(WindowState, 1);
            g_object_set_data_full(G_OBJECT(window), STATE_KEY, state, free_state);
        }
        if (!native || state->surface != surface) release(state);
        if (!native) continue;
        style_buttons(bar);
        if (!state->surface) state->surface = g_object_ref(surface);
        if (GDK_IS_WAYLAND_WINDOW(surface) && manager && !state->controls) {
            state->controls = kos_window_controls_manager_v1_get_controls(manager, gdk_wayland_window_get_wl_surface(surface));
            kos_window_controls_v1_add_listener(state->controls, &listener, window);
            /* Empty, disabled layout declares existing client-owned controls. */
            struct wl_array buttons;
            wl_array_init(&buttons);
            kos_window_controls_v1_set_buttons(state->controls, &buttons, 0);
            wl_array_release(&buttons);
            gtk_widget_queue_draw(window);
        } else if (GDK_IS_X11_WINDOW(surface) && !state->native) {
            const gulong value = 1;
            gdk_property_change(surface, gdk_atom_intern_static_string(X_PROPERTY),
                gdk_atom_intern_static_string("CARDINAL"), 32, GDK_PROP_MODE_REPLACE,
                (const guchar *)&value, 1);
        }
        state->native = TRUE;
    }
    g_list_free(windows);
    return G_SOURCE_REMOVE;
}
static void schedule(void) { if (!idle) idle = g_idle_add(inspect, NULL); }
static gboolean changed(GSignalInvocationHint *hint, guint count, const GValue *values, gpointer unused) {
    GtkWidget *widget = g_value_get_object(values);
    if (GTK_IS_WINDOW(widget) || GTK_IS_HEADER_BAR(widget)
        || gtk_widget_get_ancestor(widget, GTK_TYPE_HEADER_BAR)) schedule();
    return TRUE;
}
static void global(void *data, struct wl_registry *r, uint32_t name, const char *interface, uint32_t version) {
    if (!manager && !strcmp(interface, "kos_window_controls_manager_v1") && version >= 2) {
        manager = wl_registry_bind(r, name, &kos_window_controls_manager_v1_interface, 2);
        manager_name = name;
        schedule();
    }
}
static void removed(void *data, struct wl_registry *r, uint32_t name) {
    if (!manager || name != manager_name) return;
    GList *windows = gtk_window_list_toplevels();
    for (GList *it = windows; it; it = it->next) {
        WindowState *state = g_object_get_data(G_OBJECT(it->data), STATE_KEY);
        if (state) release(state);
    }
    g_list_free(windows);
    kos_window_controls_manager_v1_destroy(manager);
    manager = NULL;
}
static const struct wl_registry_listener registry_listener = { global, removed };
G_MODULE_EXPORT void gtk_module_init(gint *argc, gchar ***argv) {
    static gboolean initialized;
    if (initialized) return;
    initialized = TRUE;
    GdkDisplay *display = gdk_display_get_default();
    g_debug("module initialized; display=%s", display ? G_OBJECT_TYPE_NAME(display) : "none");
    if (GDK_IS_WAYLAND_DISPLAY(display)) {
        registry = wl_display_get_registry(gdk_wayland_display_get_wl_display(display));
        wl_registry_add_listener(registry, &registry_listener, NULL);
    }
    gpointer widget_class = g_type_class_ref(GTK_TYPE_WIDGET);
    const char *signals[] = {"map", "unmap", "size-allocate", "show", "hide"};
    for (guint i = 0; i < G_N_ELEMENTS(signals); i++)
        g_signal_add_emission_hook(g_signal_lookup(signals[i], GTK_TYPE_WIDGET), 0, changed, NULL, NULL);
    g_type_class_unref(widget_class);
    schedule();
}
