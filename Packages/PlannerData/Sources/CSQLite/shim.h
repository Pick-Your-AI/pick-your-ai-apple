#include <sqlite3.h>

// Swift cannot call sqlite3_db_config's variadic interface directly.
// Check both the result and effective setting before the first database read.
static inline int planner_sqlite_disable_checkpoint_on_close(sqlite3 *database) {
    int disabled = 0;
    int result = sqlite3_db_config(database, SQLITE_DBCONFIG_NO_CKPT_ON_CLOSE, 1, &disabled);
    if (result != SQLITE_OK) return result;
    return disabled == 1 ? SQLITE_OK : SQLITE_ERROR;
}
