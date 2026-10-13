/* Exercise WebKit's helper process and GTK resources, without external network. */
#include <webkit2/webkit2.h>

static int result = 1;

static gboolean timed_out(gpointer unused) {
  (void)unused;
  g_printerr("WebKit smoke test timed out\n");
  gtk_main_quit();
  return G_SOURCE_REMOVE;
}

static void loaded(WebKitWebView *view, WebKitLoadEvent event, gpointer unused) {
  (void)unused;
  g_printerr("WebKit load stage %d: %s\n", event, webkit_web_view_get_title(view));
  if (event == WEBKIT_LOAD_FINISHED &&
      g_strcmp0(webkit_web_view_get_title(view), "Venera AppImage smoke") == 0) {
    result = 0;
    gtk_main_quit();
  }
}

static void title_changed(WebKitWebView *view, GParamSpec *property, gpointer unused) {
  (void)property;
  (void)unused;
  if (g_strcmp0(webkit_web_view_get_title(view), "Venera AppImage smoke") == 0) {
    result = 0;
    gtk_main_quit();
  }
}

static void terminated(WebKitWebView *view, WebKitWebProcessTerminationReason reason, gpointer unused) {
  (void)view;
  (void)unused;
  g_printerr("WebKit process terminated: %d\n", reason);
  gtk_main_quit();
}

int main(int argc, char **argv) {
  gtk_init(&argc, &argv);
  if (g_strcmp0(g_getenv("VENERA_SMOKE_SANDBOX"), "1") == 0) {
    webkit_web_context_set_sandbox_enabled(webkit_web_context_get_default(), TRUE);
    if (!webkit_web_context_get_sandbox_enabled(webkit_web_context_get_default())) {
      g_printerr("WebKit sandbox was not enabled\n");
      return 1;
    }
  }
  GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  WebKitWebView *view = WEBKIT_WEB_VIEW(webkit_web_view_new());
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  g_signal_connect(view, "load-changed", G_CALLBACK(loaded), NULL);
  g_signal_connect(view, "notify::title", G_CALLBACK(title_changed), NULL);
  g_signal_connect(view, "web-process-terminated", G_CALLBACK(terminated), NULL);
  gtk_widget_show_all(window);
  g_timeout_add_seconds(40, timed_out, NULL);
  webkit_web_view_load_html(view,
      "<html><head><title>Venera AppImage smoke</title></head>"
      "<body>WebKit helper process works</body></html>", "about:blank");
  gtk_main();
  return result;
}
