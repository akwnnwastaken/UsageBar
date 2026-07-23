#include "UsageBarProcessLauncher.h"

#include <errno.h>
#include <util.h>
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

int usagebar_spawn_in_pty(
    const char *executable,
    char *const argv[],
    char *const envp[],
    const char *working_directory,
    pid_t *pid_out,
    int *master_fd_out
) {
    if (executable == NULL || argv == NULL || argv[0] == NULL ||
        envp == NULL || working_directory == NULL ||
        pid_out == NULL || master_fd_out == NULL) {
        return EINVAL;
    }

    int master_fd = -1;
    struct winsize terminal_size = {
        .ws_row = 24,
        .ws_col = 120,
        .ws_xpixel = 0,
        .ws_ypixel = 0
    };
    pid_t pid = forkpty(&master_fd, NULL, NULL, &terminal_size);
    if (pid < 0) {
        return errno;
    }

    if (pid == 0) {
        if (chdir(working_directory) != 0) {
            _exit(126);
        }
        execve(executable, argv, envp);
        _exit(127);
    }

    *pid_out = pid;
    *master_fd_out = master_fd;
    return 0;
}
