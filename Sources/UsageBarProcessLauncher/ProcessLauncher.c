#include "UsageBarProcessLauncher.h"

#include <errno.h>
#include <unistd.h>

int usagebar_exec_in_new_process_group(int argc, char *const argv[]) {
    if (argc < 1 || argv == NULL || argv[0] == NULL) {
        return EINVAL;
    }
    if (setpgid(0, 0) != 0) {
        return errno;
    }
    execv(argv[0], argv);
    return errno;
}
