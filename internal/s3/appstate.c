/* appstate.c — process-global handles for the S3 server's request
 * handlers. Aether http handlers are plain C callbacks (req, res, ud)
 * and the examples thread no user_data, so the db connection + data dir
 * are held here as process statics and read by handlers via the
 * appstate_* externs. Single-process server: no locking needed beyond
 * what sqlite itself provides (the handle is set once at startup). */

#include <string.h>
#include <stdlib.h>

static void* g_db = 0;
static char  g_data_dir[4096] = {0};

void appstate_set_db(void* db) { g_db = db; }
void* appstate_get_db(void) { return g_db; }

void appstate_set_data_dir(const char* dir) {
    if (!dir) { g_data_dir[0] = 0; return; }
    strncpy(g_data_dir, dir, sizeof(g_data_dir) - 1);
    g_data_dir[sizeof(g_data_dir) - 1] = 0;
}

const char* appstate_get_data_dir(void) { return g_data_dir; }
