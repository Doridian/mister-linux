#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <time.h>
#include <string.h>
#include <fcntl.h>
#include <termios.h>

#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>

#define SQUASHFS_MAGIC 0x73717368

#define ROOT_FLOPPY_MODE_ARG "rootfloppymode="

#define FLOPPY_MODE_DIRECT 0
#define FLOPPY_MODE_OVERLAY 1
#define FLOPPY_MODE_COPY 2
#define FLOPPY_MODE_UNKNOWN 100

static int switch_root(char *newroot, char *newinit)
{
	if (chdir(newroot)) {
		perror("chdir_newroot");
		return 1;
	}

	if (mount(".", "/", NULL, MS_MOVE, NULL)) {
		perror("mount_move_root");
        return 1;
	}

	if (chroot(".")) {
        perror("chroot_newroot");
        return 1;
    }
    if (chdir("/")) {
        perror("chdir_newroot");
        return 1;
    }

	execl(newinit, newinit, NULL);
	perror("exec_init");
    return 1;
}

struct termios orig_term;

static void set_tty_raw() {
    if (!isatty(STDIN_FILENO)) {
        return;
    }
    tcgetattr(STDIN_FILENO, &orig_term);
    struct termios term;
    tcgetattr(STDIN_FILENO, &term);
    cfmakeraw(&term);
    tcsetattr(STDIN_FILENO, TCSANOW, &term);
}

static void reset_tty() {
    if (!isatty(STDIN_FILENO)) {
        return;
    }
    tcsetattr(STDIN_FILENO, TCSANOW, &orig_term);
}

static int check_floppy(const char* fname) {
    int fd = open(fname, O_RDONLY);
    if (fd < 1) {
        return 0;
    }
    uint32_t fs_magic;
    if (read(fd, &fs_magic, sizeof(fs_magic)) != sizeof(fs_magic)) {
        close(fd);
        return 0;
    }
    close(fd);

    if (fs_magic == SQUASHFS_MAGIC) {
        return 1;
    }
    return 0;
}

static int exec_from_floppy(const char* prog, char *const* argv) {
    pid_t pid = fork();
    if (pid < 0) {
        return -1;
    }
    if (pid > 0) {
        int status;
        waitpid(pid, &status, 0);
        return WEXITSTATUS(status);
    }

    if (chroot("/floppy")) {
        exit(1);
        return 1;
    }

    if (chdir("/")) {
        exit(1);
        return 1;
    }

    execv(prog, argv);
    exit(1);
    return 1;
}

static int modprobe_from_floppy(char* mod) {
    return exec_from_floppy("/sbin/modprobe", (char *const[]){"/sbin/modprobe", mod, NULL});
}

static int mount_floppy(const char* fn, const int mode) {
    if(mount(fn, "/floppy", "squashfs", MS_RDONLY, NULL)) {
        perror("mount_floppy");
        return 1;
    }
    printf("Floppy disk mounted!\n");

    if (mode == FLOPPY_MODE_OVERLAY) {
        if(mount("none", "/tmpfs", "tmpfs", 0, NULL)) {
            perror("mount_tmpfs");
            return 1;
        }
        if(mkdir("/tmpfs/work", 0755)) {
            perror("mkdir_tmpfs_work");
            return 1;
        }
        if(mkdir("/tmpfs/upper", 0755)) {
            perror("mkdir_tmpfs_upper");
            return 1;
        }

        printf("Loading overlay kmod...\n");
        if (modprobe_from_floppy("overlay")) {
            perror("load_overlay_kmod");
            return 1;
        }
        printf("Mounting overlay...\n");
        if(mount("overlay", "/newroot", "overlay", 0, "lowerdir=/floppy,upperdir=/tmpfs/upper,workdir=/tmpfs/work")) {
            perror("mount_overlay");
            return 1;
        }
        printf("Mounting /overlay/floppy...\n");
        if(mount("/floppy", "/newroot/overlay/floppy", NULL, MS_MOVE, NULL)) {
            perror("mount_move_floppy");
            return 1;
        }
        printf("Mounting /overlay/tmpfs...\n");
        if (mount("/tmpfs", "/newroot/overlay/tmpfs", NULL, MS_MOVE, NULL)) {
            perror("mount_move_tmpfs");
            return 1;
        }
    } else if (mode == FLOPPY_MODE_DIRECT) { 
        if (mount("/floppy", "/newroot", NULL, MS_MOVE, NULL)) {
            perror("mount_move_floppy");
            return 1;
        }
    } else if (mode == FLOPPY_MODE_COPY) {
        if(mount("none", "/floppy/overlay/tmpfs", "tmpfs", 0, NULL)) {
            perror("mount_tmpfs_newroot");
            return 1;
        }

        if(mount(fn, "/floppy/overlay/floppy", "squashfs", MS_RDONLY, NULL)) {
            perror("mount_floppy_copy");
            return 1;
        }

        exec_from_floppy("/bin/cp", (char *const[]){"/bin/cp", "-a", "/overlay/floppy/.", "/overlay/tmpfs/", NULL});

        printf("Moving mount /floppy/overlay/tmpfs to /newroot...\n");
        if(mount("/floppy/overlay/tmpfs", "/newroot", NULL, MS_MOVE, NULL)) {
            perror("mount_move_floppy");
            return 1;
        }
        printf("Unmounting /floppy, /floppy/overlay/floppy...\n");
        if (umount("/floppy/overlay/floppy") || umount("/floppy")) {
            perror("umount_floppy_copy");
            return 1;
        }
    }

    printf("Unmounting old /dev...\n");
    if (umount("/dev")) {
        perror("umount_dev");
        return 1;
    }
    printf("Removing old /dev entries...\n");
    if (unlink("/dev/console") || unlink("/dev/tty0") || unlink("/dev/tty1")) {
        perror("rm_old_dev");
        return 1;
    }
    printf("Removing old /tmpfs, /dev and /floppy...\n");
    if (rmdir("/dev") || rmdir("/tmpfs") || rmdir("/floppy")) {
        perror("rm_old_dirs");
        return 1;
    }
    printf("Removing self...\n");
    if (unlink("/init")) {
        perror("rm_self");
        return 1;
    }

    printf("Switching root...\n");
    switch_root("/newroot", "/sbin/init");
    return 1;
}

static int floppy_mode_from_char(const char c) {
    if (c == 'D' || c == 'd') {
        return FLOPPY_MODE_DIRECT;
    } else if (c == 'O' || c == 'o') {
        return FLOPPY_MODE_OVERLAY;
    } else if (c == 'C' || c == 'c') {
        return FLOPPY_MODE_COPY;
    }
    return FLOPPY_MODE_UNKNOWN;
}

int main(int argc, char *argv[]) {
    if(mount("none", "/dev", "devtmpfs", 0, NULL)) {
        perror("mount_devtmpfs");
        return 1;
    }

    int mode = FLOPPY_MODE_OVERLAY;

    for (int i=0; i<argc; ++i) {
        if (strncmp(argv[i], ROOT_FLOPPY_MODE_ARG, strlen(ROOT_FLOPPY_MODE_ARG)) == 0) {
            mode = floppy_mode_from_char(argv[i][strlen(ROOT_FLOPPY_MODE_ARG)]);
        }
    }

    set_tty_raw();
    for (int timeout_seconds_remain = 5; timeout_seconds_remain > 0; timeout_seconds_remain--) {
        char dmode = 'd';
        char omode = 'o';
        char cmode = 'c';

        if (mode == FLOPPY_MODE_DIRECT) {
            dmode = 'D';
        } else if (mode == FLOPPY_MODE_OVERLAY) {
            omode = 'O';
        } else if (mode == FLOPPY_MODE_COPY) {
            cmode = 'C';
        }

        printf("\r\nTo manually override the floppy mode, within %d seconds, please\r\nchoose (D)irect, (O)verlay or (O)opy [%c%c%c]: ", timeout_seconds_remain, dmode, omode, cmode);
        fflush(stdout);

        struct timeval timeout = {1, 0};
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(STDIN_FILENO, &fds);
        int ret = select(1, &fds, NULL, NULL, &timeout);

        if (ret > 0) {
            int newmode = floppy_mode_from_char(getchar());
            if (newmode != FLOPPY_MODE_UNKNOWN) {
                mode = newmode;
            }
            break;
        }
    }
    reset_tty();

    printf("\nFloppy mode: ");
    switch (mode) {
        case FLOPPY_MODE_DIRECT:
            printf("direct\n");
            break;
        case FLOPPY_MODE_OVERLAY:
            printf("overlay\n");
            break;
        case FLOPPY_MODE_COPY:
            printf("copy\n");
            break;
        default:
            printf("unknown\n");
            return 1;
    }

    printf("Scanning for root floppy...\n");

    while (1) {
        for (int i = 0; i < 10; i++) {
            char fn[32];
            sprintf(fn, "/dev/fd%d", i);
            printf("Querying device: %s\n", fn);
            if (check_floppy(fn)) {
                printf("Floppy disk detected: %s\n", fn);
                return mount_floppy(fn, mode);
            }
        }

        printf("No floppy disk detected, hit ENTER to retry...\n");
        set_tty_raw();
        if (getchar() <= 0) {
            sleep(1);
        }
        reset_tty();
    }

    return 1;
}
