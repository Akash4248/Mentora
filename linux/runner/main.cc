#include "my_application.h"

int main(int argc, char** argv) {
  // On Ubuntu 24.04+ (GNOME 46+), GTK3's Wayland backend attempts to query the
  // deprecated GSettings key 'antialiasing' in 'org.gnome.settings-daemon.plugins.xsettings',
  // which causes a fatal GLib-GIO abort when running directly under Wayland.
  // Setting GDK_BACKEND to x11 uses XWayland safely unless explicitly overridden.
  if (g_getenv("GDK_BACKEND") == nullptr) {
    g_setenv("GDK_BACKEND", "x11", FALSE);
  }

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
